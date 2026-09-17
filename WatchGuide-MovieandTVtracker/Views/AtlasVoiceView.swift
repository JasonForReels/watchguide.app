//
//  AtlasVoiceView.swift
//  WatchGuide-MovieandTVtracker
//
//  Full-screen immersive voice UI for Ask Atlas. Presented as a sheet from the
//  mic button in the chat input bar. Drives an AtlasVoiceSession (Gemini Live)
//  and is entirely separate from the text chat.
//
//  iOS-only (depends on AtlasVoiceSession / AVAudioSession).
//

import SwiftUI

#if os(iOS)

struct AtlasVoiceView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var session = AtlasVoiceSession()
    @State private var showPaywall = false
    @State private var showTuning = false
    @AppStorage(AtlasVoice.storageKey) private var storedVoice = AtlasVoice.defaultVoice.rawValue

    // Expression axes (0...1), persisted individually so they survive launches.
    @AppStorage(AtlasVoiceExpression.Key.energy) private var energy = AtlasVoiceExpression.default.energy
    @AppStorage(AtlasVoiceExpression.Key.warmth) private var warmth = AtlasVoiceExpression.default.warmth
    @AppStorage(AtlasVoiceExpression.Key.pace) private var pace = AtlasVoiceExpression.default.pace
    @AppStorage(AtlasVoiceExpression.Key.drama) private var drama = AtlasVoiceExpression.default.drama

    private var selectedVoice: AtlasVoice {
        AtlasVoice(rawValue: storedVoice) ?? .defaultVoice
    }

    private var currentExpression: AtlasVoiceExpression {
        AtlasVoiceExpression(energy: energy, warmth: warmth, pace: pace, drama: drama)
    }

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                topBar
                Spacer()
                AtlasVoiceWavePanel(session: session)
                Spacer()
                controls
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            if case .ended(let reason) = session.phase {
                endedOverlay(reason: reason)
            }

            // Tune is an in-view overlay (NOT a sheet): presenting a sheet from
            // inside the voice fullScreenCover was rebuilding this view and
            // spawning duplicate audio sessions. An overlay can't be torn down
            // by presentation churn.
            if showTuning {
                AtlasVoiceTuningView(
                    storedVoice: $storedVoice,
                    energy: $energy,
                    warmth: $warmth,
                    pace: $pace,
                    drama: $drama,
                    onClose: { withAnimation(.easeInOut(duration: 0.2)) { showTuning = false } }
                )
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // Silence the app behind us before the mic opens. Every trailer
            // surface watches this flag, so hero carousels, detail-page trailers
            // and trailer rows all stand down for the duration of the call.
            HeroCarouselMuteManager.shared.isVoiceModeActive = true
            await session.start(
                voice: selectedVoice,
                expression: currentExpression,
                restrictedMode: ScoutAgeGateManager.shared.isKidsRestricted
            )
        }
        .onDisappear {
            session.end(reason: .user)
            HeroCarouselMuteManager.shared.isVoiceModeActive = false
        }
        .sheet(isPresented: $showPaywall) {
            WGUnlimitedPaywallView()
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.10),
                Color(red: 0.08, green: 0.06, blue: 0.16),
                Color.black
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            voicePicker

            Spacer()

            if let remaining = session.remainingSeconds {
                Label(timeString(remaining), systemImage: "timer")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(remaining <= 30 ? Color.orange : Color.white.opacity(0.7))
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showTuning = true }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }

            Button {
                session.end(reason: .user)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
        }
    }

    private var voicePicker: some View {
        Menu {
            Picker("Voice", selection: $storedVoice) {
                ForEach(AtlasVoice.allCases) { voice in
                    Text("\(voice.displayName) · \(voice.blurb)").tag(voice.rawValue)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                Text(selectedVoice.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        // Changing the voice mid-session has no effect until reconnecting; the
        // picker is mainly for choosing before the next session.
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 40) {
            AtlasVoiceCallButton(
                symbol: session.isMuted ? "mic.slash.fill" : "mic.fill",
                tint: session.isMuted ? Color.orange : Color.white,
                glassTint: nil,
                diameter: 64,
                accessibilityText: session.isMuted ? "Unmute" : "Mute"
            ) {
                session.toggleMute()
            }
            .disabled(!isLive)

            AtlasVoiceCallButton(
                symbol: "phone.down.fill",
                tint: .white,
                glassTint: .red,
                diameter: 64,
                accessibilityText: "End call"
            ) {
                session.end(reason: .user)
                dismiss()
            }
        }
        .padding(.bottom, 12)
    }

    private var isLive: Bool {
        switch session.phase {
        case .listening, .speaking: return true
        default: return false
        }
    }

    // MARK: - Ended Overlay

    @ViewBuilder
    private func endedOverlay(reason: AtlasVoiceSession.EndReason) -> some View {
        // A normal user-initiated end just dismisses; only show an overlay for
        // the time limit or an error.
        switch reason {
        case .user:
            Color.clear
        case .timeLimitReached:
            overlayCard(
                icon: "timer",
                title: "Voice time's up for today",
                message: session.hitQuotaLimit
                    ? "You've used today's voice minutes. Upgrade to WatchGuide Pro for unlimited voice time."
                    : "This session reached its time limit.",
                showUpgrade: true
            )
        case .error(let text):
            overlayCard(icon: "exclamationmark.triangle.fill", title: "Voice unavailable", message: text, showUpgrade: false)
        }
    }

    private func overlayCard(icon: String, title: String, message: String, showUpgrade: Bool) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                if showUpgrade {
                    Button {
                        showPaywall = true
                    } label: {
                        Text("Upgrade")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule().fill(LinearGradient(
                                    colors: [Color(red: 0.30, green: 0.50, blue: 0.98), Color(red: 0.34, green: 0.24, blue: 0.82)],
                                    startPoint: .leading, endPoint: .trailing
                                ))
                            )
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.08)))
            .padding(.horizontal, 36)
        }
    }

    // MARK: - Helpers

    private func timeString(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Wave (isolated subview)

/// The live waveform + status text. Kept as its own view so the high-frequency
/// `micLevel` updates only re-render THIS view — not `AtlasVoiceView`, which
/// hosts the Tune/paywall sheets (rapid re-renders there auto-dismiss sheets).
private struct AtlasVoiceWavePanel: View {
    let session: AtlasVoiceSession

    var body: some View {
        VStack(spacing: 26) {
            AtlasVoiceLiveWave(session: session, size: .hero)
                .padding(.horizontal, 8)

            Text(statusText)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: statusText)
        }
    }

    private var statusText: String {
        switch session.phase {
        case .idle, .connecting: return "Connecting\u{2026}"
        case .listening:         return session.isMuted ? "Muted" : "Listening\u{2026}"
        case .speaking:          return "Atlas is speaking\u{2026}"
        case .ended:             return ""
        }
    }
}

// MARK: - Tuning Sheet

/// Lets the user pick a voice, tap a personality preset, and fine-tune the
/// delivery with expression sliders. The sliders are the source of truth; a
/// preset simply moves them. All settings apply to the next session, since the
/// voice + expression are fixed in the Live API setup handshake.
struct AtlasVoiceTuningView: View {
    @Binding var storedVoice: String
    @Binding var energy: Double
    @Binding var warmth: Double
    @Binding var pace: Double
    @Binding var drama: Double
    /// Shown as an in-view overlay (not a sheet), so closing is an explicit callback.
    var onClose: () -> Void

    private var selectedVoice: AtlasVoice {
        AtlasVoice(rawValue: storedVoice) ?? .defaultVoice
    }

    private var previewNote: String {
        let note = AtlasVoiceExpression(energy: energy, warmth: warmth, pace: pace, drama: drama).directorsNote
        let trimmed = note.replacingOccurrences(of: " Delivery: speak with ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return trimmed.isEmpty ? "Balanced, natural delivery." : "Atlas will speak with \(trimmed)."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.05, blue: 0.10), Color.black],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        voiceSection
                        presetSection
                        sliderSection
                        previewSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Tune Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Voice")
            Menu {
                Picker("Voice", selection: $storedVoice) {
                    ForEach(AtlasVoice.allCases) { voice in
                        Text("\(voice.displayName) · \(voice.blurb)").tag(voice.rawValue)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "waveform")
                    Text("\(selectedVoice.displayName)")
                        .fontWeight(.semibold)
                    Text(selectedVoice.blurb)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            }
        }
    }

    // MARK: Presets

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Personality")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AtlasVoiceStyle.allCases) { style in
                        let selected = matches(style.expression)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { apply(style.expression) }
                        } label: {
                            Text(style.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selected ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        selected
                                            ? AnyShapeStyle(LinearGradient(
                                                colors: [Color(red: 0.30, green: 0.50, blue: 0.98), Color(red: 0.34, green: 0.24, blue: 0.82)],
                                                startPoint: .leading, endPoint: .trailing))
                                            : AnyShapeStyle(Color.white.opacity(0.10))
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: Sliders

    private var sliderSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("Fine-tune")
            sliderRow("Energy", low: "Calm", high: "Hyped", value: $energy, tint: .orange)
            sliderRow("Warmth", low: "Cool", high: "Warm", value: $warmth, tint: .pink)
            sliderRow("Pace", low: "Slow", high: "Quick", value: $pace, tint: .green)
            sliderRow("Drama", low: "Plain", high: "Cinematic", value: $drama, tint: .purple)
        }
    }

    private func sliderRow(_ title: String, low: String, high: String, value: Binding<Double>, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Slider(value: value, in: 0...1)
                .tint(tint)
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Preview")
            Text(previewNote)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Text("Applies to your next voice session.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    // MARK: Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.45))
            .tracking(0.5)
    }

    private func apply(_ expression: AtlasVoiceExpression) {
        energy = expression.energy
        warmth = expression.warmth
        pace = expression.pace
        drama = expression.drama
    }

    private func matches(_ expression: AtlasVoiceExpression) -> Bool {
        let epsilon = 0.001
        return abs(energy - expression.energy) < epsilon
            && abs(warmth - expression.warmth) < epsilon
            && abs(pace - expression.pace) < epsilon
            && abs(drama - expression.drama) < epsilon
    }
}

#endif
