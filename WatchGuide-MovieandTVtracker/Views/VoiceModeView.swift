//
//  VoiceModeView.swift
//  WatchGuide-MovieandTVtracker
//

import SwiftUI
import AVFoundation

struct VoiceModeMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
}

struct VoiceModeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = VoiceModeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                statusCard

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                messageBubble(message)
                                    .id(message.id)
                            }

                            if !viewModel.liveTranscript.isEmpty {
                                messageBubble(
                                    VoiceModeMessage(
                                        role: .assistant,
                                        text: viewModel.liveTranscript
                                    )
                                )
                                .id("live-transcript")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastID = viewModel.messages.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.liveTranscript) { _, value in
                        guard !value.isEmpty else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("live-transcript", anchor: .bottom)
                        }
                    }
                }

                VStack(spacing: 10) {
                    if !viewModel.partialTranscript.isEmpty {
                        Text(viewModel.partialTranscript)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await viewModel.toggleListening() }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 28, weight: .bold))
                            Text(viewModel.isListening ? "Stop Listening" : "Tap To Speak")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(viewModel.isListening ? Color.red : Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    Text("Commands like “go to search”, “scroll down”, or “jump to cast” are handled locally. Everything else goes to Gemini Live.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .padding(.top)
            .navigationTitle("Voice Mode")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.prepare()
        }
        .onDisappear {
            viewModel.teardown()
            VoiceModeCoordinator.shared.dismiss()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gemini Live")
                .font(.headline)
            Text(viewModel.connectionStatus)
                .font(.subheadline)
                .foregroundStyle(viewModel.connectionTint)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal)
    }

    private func messageBubble(_ message: VoiceModeMessage) -> some View {
        HStack {
            if message.role == .assistant {
                bubbleBody(message, alignment: .leading, fill: Color(.secondarySystemBackground), foreground: .primary)
                Spacer(minLength: 36)
            } else {
                Spacer(minLength: 36)
                bubbleBody(message, alignment: .trailing, fill: Color.accentColor, foreground: .white)
            }
        }
    }

    private func bubbleBody(
        _ message: VoiceModeMessage,
        alignment: Alignment,
        fill: Color,
        foreground: Color
    ) -> some View {
        Text(message.text)
            .font(.body)
            .foregroundStyle(foreground)
            .multilineTextAlignment(message.role == .assistant ? .leading : .trailing)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(fill)
            )
    }
}

@MainActor
final class VoiceModeViewModel: ObservableObject {
    @Published private(set) var messages: [VoiceModeMessage] = []
    @Published private(set) var partialTranscript = ""
    @Published private(set) var liveTranscript = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    var connectionStatus: String {
        liveService.connectionState.statusText
    }

    var connectionTint: Color {
        switch liveService.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .failed:
            return .red
        case .idle:
            return .secondary
        }
    }

    private let liveService = GeminiLiveService()
    private let speechService = SpeechRecognitionService()
    private let commandRouter = VoiceCommandRouter.shared
    private let synthesizer = AVSpeechSynthesizer()

    func prepare() async {
        liveService.onModelTranscriptUpdate = { [weak self] text, isFinal in
            guard let self else { return }
            self.liveTranscript = text
            if isFinal, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.messages.append(VoiceModeMessage(role: .assistant, text: text))
                self.liveTranscript = ""
            }
        }
        await liveService.connectIfNeeded()
    }

    func teardown() {
        if isListening {
            _ = speechService.stopListening()
            isListening = false
        }
        liveService.disconnect()
        synthesizer.stopSpeaking(at: .immediate)
    }

    func toggleListening() async {
        if isListening {
            await finishListening()
        } else {
            await startListening()
        }
    }

    private func startListening() async {
        errorMessage = nil
        partialTranscript = ""
        do {
            try await speechService.startListening()
            isListening = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                while self.speechService.isListening {
                    self.partialTranscript = self.speechService.transcript
                    try? await Task.sleep(for: .milliseconds(120))
                }
                self.partialTranscript = self.speechService.transcript
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishListening() async {
        let transcript = speechService.stopListening()
        isListening = false
        partialTranscript = transcript
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(VoiceModeMessage(role: .user, text: trimmed))
        partialTranscript = ""

        if let commandResult = commandRouter.handle(trimmed) {
            messages.append(VoiceModeMessage(role: .assistant, text: commandResult.assistantText))
            speakLocally(commandResult.assistantText)
            return
        }

        await liveService.sendUserTurn(trimmed)
    }

    private func speakLocally(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
