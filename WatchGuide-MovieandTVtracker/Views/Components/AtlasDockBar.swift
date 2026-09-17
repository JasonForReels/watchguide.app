//
//  AtlasDockBar.swift
//  WatchGuide-MovieandTVtracker
//
//  Atlas, in place. There is no Atlas page: this bar along the bottom of the
//  screen is the whole surface. It takes the tab bar's slot rather than
//  stacking on it, so engaging Atlas costs no extra vertical space.
//
//  Two heights, on one continuous piece of glass:
//
//    .reply     the resting size — one reply, then it scrolls inside the cap
//    .expanded  the full transcript, grown in place
//
//  Drag the grabber (or tap it) to move between them; drag down from .reply to
//  put Atlas away. Imagine is the one thing that still gets its own sheet — it
//  is an image generator, not a conversation, and it needs the room.
//

import SwiftUI

#if !os(tvOS)

// MARK: - Engagement state

/// Shared so the bar (an overlay above the TabView) and the tab bar itself
/// (inside it) can agree on who owns the bottom of the screen.
@MainActor
final class AtlasDockState: ObservableObject {
    static let shared = AtlasDockState()

    enum Detent {
        /// Resting: the input row plus at most one reply.
        case reply
        /// Grown in place: the full conversation.
        case expanded
    }

    /// True while the bar has replaced the tab bar.
    @Published private(set) var isEngaged = false
    @Published var detent: Detent = .reply

    private init() {}

    static let transition: Animation = .spring(response: 0.42, dampingFraction: 0.82)

    func engage(at detent: Detent = .reply) {
        self.detent = detent
        guard !isEngaged else { return }
        withAnimation(Self.transition) { isEngaged = true }
    }

    func dismiss() {
        guard isEngaged else { return }
        withAnimation(Self.transition) {
            isEngaged = false
            detent = .reply
        }
    }

    func setDetent(_ new: Detent) {
        guard detent != new else { return }
        withAnimation(Self.transition) { detent = new }
    }
}

// MARK: - Bar

struct AtlasDockBar: View {
    /// Height the bar has to live within — the expanded detent is a fraction of
    /// it, so the bar adapts to the device and to the keyboard being up.
    let availableHeight: CGFloat
    /// Opens the live voice session.
    let onVoice: () -> Void

    @ObservedObject private var viewModel = AIAssistantViewModel.shared
    @ObservedObject private var inputState = AIAssistantViewModel.shared.inputState
    @ObservedObject private var dock = AtlasDockState.shared

    @AppStorage(AtlasPersona.storageKey) private var personaRaw = AtlasPersona.default.rawValue
    @FocusState private var isInputFocused: Bool

    @State private var showImagine = false
    /// Live offset while the grabber is being dragged, so the glass tracks the
    /// finger before it settles into a detent.
    @State private var dragTranslation: CGFloat = 0
    /// The mark starts erased and draws itself on as the bar arrives, picking
    /// up where the orb's draw-off left off.
    @State private var isMarkErased = true

    /// The tallest the resting reply is allowed to get — one reply, then scroll.
    private let replyCap: CGFloat = 170
    private let corner: CGFloat = 28

    private var persona: AtlasPersona {
        AtlasPersona(rawValue: personaRaw) ?? .default
    }

    /// The most recent thing Atlas said, with control tags stripped.
    private var latestReply: String? {
        guard let message = viewModel.messages.last(where: { $0.role == "assistant" }) else { return nil }
        let cleaned = AtlasDockBar.stripControlTags(message.content)
        return cleaned.isEmpty ? nil : cleaned
    }

    private var hasReplyArea: Bool {
        viewModel.isThinking || latestReply != nil
    }

    /// Expanded stops short of the full height on purpose — the point of staying
    /// in place is that you can still see what you were looking at.
    private var expandedCap: CGFloat {
        max(240, availableHeight * 0.58)
    }

    private var canExpand: Bool {
        viewModel.messageCount > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            contentArea
            if hasReplyArea || dock.detent == .expanded {
                Divider().opacity(0.4)
            }
            #if os(iOS)
            if let notice = AtlasInlineVoice.shared.endedNotice {
                voiceNotice(notice)
            }
            #endif
            inputRow
        }
        .frame(maxWidth: .infinity)
        .modifier(DockGlassBackground(corner: corner))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .padding(.horizontal, 10)
        .offset(y: max(0, dragTranslation))
        .task {
            isInputFocused = true
            isMarkErased = false
        }
        #if os(iOS)
        // A call can end on its own (budget, dropped socket). Fold the bar back
        // to the composer when it does, instead of leaving a dead wave sitting
        // in the text slot.
        .onChange(of: AtlasInlineVoice.shared.session?.phase) { _, phase in
            guard case .ended(let reason) = phase else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                AtlasInlineVoice.shared.handleSessionEnded(reason)
            }
            isInputFocused = true
        }
        .onDisappear {
            // The bar going away means the call goes with it — an invisible
            // open microphone is not a thing we ship.
            AtlasInlineVoice.shared.end()
        }
        #endif
        .sheet(isPresented: $showImagine) {
            AtlasImagineSheet { imageData in
                inputState.addImage(imageData)
                showImagine = false
                isInputFocused = true
            }
        }
    }

    // MARK: Grabber

    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.28))
            .frame(width: 38, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(detentDrag)
            .onTapGesture { toggleDetent() }
            .accessibilityElement()
            .accessibilityLabel(dock.detent == .expanded ? "Collapse Atlas" : "Expand Atlas")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleDetent() }
    }

    private var detentDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // Only the downward drag tracks the finger; upward just expands.
                dragTranslation = dock.detent == .expanded ? value.translation.height
                                                           : max(0, value.translation.height)
                if value.translation.height < -30, dock.detent == .reply, canExpand {
                    dragTranslation = 0
                    dock.setDetent(.expanded)
                }
            }
            .onEnded { value in
                let travel = value.translation.height
                withAnimation(AtlasDockState.transition) { dragTranslation = 0 }

                if travel > 60 {
                    if dock.detent == .expanded {
                        dock.setDetent(.reply)
                    } else {
                        isInputFocused = false
                        dock.dismiss()
                    }
                } else if travel < -40, canExpand {
                    dock.setDetent(.expanded)
                }
            }
    }

    private func toggleDetent() {
        if dock.detent == .expanded {
            dock.setDetent(.reply)
        } else if canExpand {
            dock.setDetent(.expanded)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentArea: some View {
        switch dock.detent {
        case .expanded:
            AIMessageListView(viewModel: viewModel,
                              dismissKeyboard: { isInputFocused = false })
                .frame(maxHeight: expandedCap)
                .transition(.opacity)
        case .reply:
            if hasReplyArea {
                replyArea.transition(.opacity)
            }
        }
    }

    private var replyArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if let reply = latestReply {
                        Text(reply)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if viewModel.isThinking {
                        thinkingMark
                    }
                    Color.clear.frame(height: 1).id(AtlasDockBar.replyBottomAnchor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .animation(.easeInOut(duration: 0.22), value: viewModel.isThinking)
            }
            .frame(maxHeight: replyCap)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: latestReply) { _, _ in
                // Follow the stream as it lands, rather than stranding the user
                // at the top of a reply that's still being written.
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(AtlasDockBar.replyBottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isThinking) { _, thinking in
                // Carry the last answer up out of the way so the mark has the
                // space — the reply you've already read yields to the one being
                // written.
                guard thinking else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    proxy.scrollTo(AtlasDockBar.replyBottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    /// Waiting is the mark drawing itself, centred in the reply area rather
    /// than tucked into a corner as a spinner. With nothing above it yet it
    /// takes the whole space; once there's a reply to sit under, it needs less.
    private var thinkingMark: some View {
        AtlasMark(size: 26, isThinking: true)
            // With nothing above it the block fills the resting cap, so the
            // mark lands in the middle of the bar rather than up near the
            // grabber. `- 16` is the reply area's own top and bottom padding.
            .frame(maxWidth: .infinity,
                   minHeight: latestReply == nil ? replyCap - 16 : 46)
            .accessibilityElement()
            .accessibilityLabel("Thinking")
            .transition(.opacity)
    }

    // MARK: Input

    #if os(iOS)
    private func voiceNotice(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { AtlasInlineVoice.shared.clearNotice() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(.white.opacity(0.62))
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .transition(.opacity)
    }
    #endif

    private var inputRow: some View {
        HStack(spacing: 10) {
            #if os(iOS)
            if let session = AtlasInlineVoice.shared.session {
                voiceRow(session: session)
            } else {
                composerRow
            }
            #else
            composerRow
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.top, hasReplyArea || dock.detent == .expanded ? 10 : 4)
        .padding(.bottom, 10)
        #if os(iOS)
        .animation(.spring(response: 0.38, dampingFraction: 0.86),
                   value: AtlasInlineVoice.shared.isActive)
        #endif
    }

    /// The resting composer: type, attach, or start talking.
    @ViewBuilder
    private var composerRow: some View {
        // The same mark the orb carries, picking up the cycle the press on the
        // orb started — the bar reads as the orb grown open, not a new object.
        AtlasMark(size: 19, isErased: isMarkErased)
            .accessibilityHidden(true)

        TextField("Ask Atlas\u{2026}", text: $inputState.inputText, axis: .vertical)
            .lineLimit(1...3)
            .font(.body)
            .foregroundStyle(.white)
            .focused($isInputFocused)
            .submitLabel(.send)
            .onSubmit(send)

        if inputState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            iconButton("wand.and.stars", label: "Imagine") { showImagine = true }
            voiceButton
        } else {
            sendButton
        }

        iconButton("chevron.down", label: "Close Atlas") {
            isInputFocused = false
            dock.dismiss()
        }
    }

    @ViewBuilder
    private var voiceButton: some View {
        #if os(iOS)
        // Tap talks to Atlas right here in the bar; press-and-hold takes the
        // conversation full screen for the tuning controls and the timer.
        iconButton("waveform", label: "Voice mode") {
            isInputFocused = false
            AtlasInlineVoice.shared.start()
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            onVoice()
        })
        #else
        iconButton("waveform", label: "Voice mode", action: onVoice)
        #endif
    }

    #if os(iOS)
    /// The call, running in the composer's own slot: the wave takes the text
    /// field, and mute + hang up take Imagine and the close chevron. Nothing
    /// moves, so the AI reads as part of the bar rather than a screen over it.
    @ViewBuilder
    private func voiceRow(session: AtlasVoiceSession) -> some View {
        AtlasVoiceLiveWave(session: session, size: .inline)
            .transition(.opacity.combined(with: .scale(scale: 0.94)))

        AtlasVoiceCallButton(
            symbol: session.isMuted ? "mic.slash.fill" : "mic.fill",
            tint: session.isMuted ? .orange : .white,
            glassTint: nil,
            diameter: 34,
            accessibilityText: session.isMuted ? "Unmute" : "Mute"
        ) {
            AtlasInlineVoice.shared.toggleMute()
        }

        AtlasVoiceCallButton(
            symbol: "phone.down.fill",
            tint: .white,
            glassTint: .red,
            diameter: 34,
            accessibilityText: "End call"
        ) {
            AtlasInlineVoice.shared.end()
            isInputFocused = true
        }
    }
    #endif

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white, persona.accentColor)
                .symbolEffect(.bounce, value: viewModel.messageCount)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send")
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func send() {
        let trimmed = inputState.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        Task { await viewModel.sendMessage() }
    }

    // MARK: Helpers

    private static let replyBottomAnchor = "atlas-dock-reply-bottom"

    /// Strips `[TRAILER:…]`, `[ACTION:…]`, `[REMEMBER:…]` and friends. The
    /// expanded transcript renders those as rich UI; the resting reply shows
    /// prose only.
    static func stripControlTags(_ text: String) -> String {
        text.replacingOccurrences(of: "\\[[A-Z_]+:[^\\]]*\\]",
                                  with: "",
                                  options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Glass background

/// The bar carries text, so it uses `.regular` rather than the orb's `.clear`:
/// a clear lens behind a paragraph is a paragraph you can't read.
private struct DockGlassBackground: ViewModifier {
    let corner: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: corner))
        } else {
            content.background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

#endif
