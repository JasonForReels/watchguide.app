//
//  SpeechRecognitionService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation
#if canImport(Speech)
import Speech
import AVFoundation
#endif

@MainActor
final class SpeechRecognitionService: ObservableObject {
    enum RecognitionError: LocalizedError {
        case unavailable
        case permissionDenied
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Voice input is not available on this device."
            case .permissionDenied:
                return "Microphone or speech recognition permission was denied."
            case .recognizerUnavailable:
                return "Speech recognition is currently unavailable."
            }
        }
    }

    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false

    #if canImport(Speech)
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    #endif

    func startListening() async throws {
        #if canImport(Speech)
        guard speechRecognizer != nil else { throw RecognitionError.unavailable }
        try await requestPermissionsIfNeeded()

        transcript = ""
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }

            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.finishRecognitionSession()
                }
            }
        }
        #else
        throw RecognitionError.unavailable
        #endif
    }

    func stopListening() -> String {
        #if canImport(Speech)
        finishRecognitionSession()
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return ""
        #endif
    }

    #if canImport(Speech)
    private func finishRecognitionSession() {
        guard isListening || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
    }

    private func requestPermissionsIfNeeded() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        guard speechStatus == .authorized, microphoneGranted else {
            throw RecognitionError.permissionDenied
        }

        guard speechRecognizer?.isAvailable == true else {
            throw RecognitionError.recognizerUnavailable
        }
    }
    #endif
}
