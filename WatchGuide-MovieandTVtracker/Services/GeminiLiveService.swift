//
//  GeminiLiveService.swift
//  WatchGuide-MovieandTVtracker
//

import Foundation
import AVFoundation

@MainActor
final class GeminiLiveService: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)

        var statusText: String {
            switch self {
            case .idle:
                return "Idle"
            case .connecting:
                return "Connecting"
            case .connected:
                return "Connected"
            case .failed(let message):
                return message
            }
        }
    }

    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var isResponding = false

    var onModelTranscriptUpdate: ((String, Bool) -> Void)?

    private let modelName = "models/gemini-2.5-flash-native-audio-preview-12-2025"
    private let endpoint = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
    private let audioPlayer = PCM16StreamPlayer()

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var currentTranscript = ""
    private var didSendSetup = false

    func connectIfNeeded() async {
        guard socket == nil else { return }
        guard let apiKey = ApiKeyManager.shared.get(key: "GEMINI_API_KEY"), !apiKey.isEmpty else {
            connectionState = .failed("Missing Gemini API key")
            return
        }

        connectionState = .connecting

        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration)
        self.session = session

        var request = URLRequest(url: endpoint)
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let socket = session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()

        do {
            try await sendSetup()
            connectionState = .connected
            receiveLoop()
        } catch {
            connectionState = .failed("Gemini Live connection failed")
            disconnect()
        }
    }

    func disconnect() {
        isResponding = false
        currentTranscript = ""
        didSendSetup = false
        audioPlayer.stopAndReset()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        if case .failed = connectionState {
            return
        }
        connectionState = .idle
    }

    func sendUserTurn(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await connectIfNeeded()
        guard socket != nil, case .connected = connectionState else { return }

        currentTranscript = ""
        isResponding = true
        audioPlayer.stopAndReset()
        onModelTranscriptUpdate?("", false)

        let payload: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "turnComplete": true
            ]
        ]

        do {
            try await sendJSON(payload)
        } catch {
            connectionState = .failed("Failed to send request")
            isResponding = false
        }
    }

    private func sendSetup() async throws {
        guard !didSendSetup else { return }
        didSendSetup = true

        let setupPayload: [String: Any] = [
            "setup": [
                "model": modelName,
                "generationConfig": [
                    "responseModalities": ["AUDIO"]
                ],
                "systemInstruction": [
                    "parts": [
                        [
                            "text": """
                            You are Watch Guide Voice Mode. Keep responses concise and natural for spoken delivery.
                            If the user's request is clearly a direct app navigation or detail scrolling command, do not over-explain.
                            Focus on helping with movies, shows, and what is currently visible in the app.
                            """
                        ]
                    ]
                ],
                "outputAudioTranscription": [:]
            ]
        ]

        try await sendJSON(setupPayload)
    }

    private func sendJSON(_ payload: [String: Any]) async throws {
        guard let socket else { return }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let string = String(data: data, encoding: .utf8) else { return }
        try await socket.send(.string(string))
    }

    private func receiveLoop() {
        guard let socket else { return }

        socket.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop()
                case .failure:
                    self.connectionState = .failed("Gemini Live disconnected")
                    self.disconnect()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            text = String(decoding: data, as: UTF8.self)
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if json["setupComplete"] != nil {
            connectionState = .connected
        }

        if let serverContent = json["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
        }

        if let outputTranscription = json["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String {
            currentTranscript = text
            onModelTranscriptUpdate?(text, false)
        }
    }

    private func handleServerContent(_ serverContent: [String: Any]) {
        if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
            audioPlayer.stopAndReset()
            isResponding = false
        }

        if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
           let text = outputTranscription["text"] as? String {
            currentTranscript = text
            onModelTranscriptUpdate?(text, false)
        }

        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    currentTranscript = text
                    onModelTranscriptUpdate?(text, false)
                }

                if let inlineData = part["inlineData"] as? [String: Any],
                   let mimeType = inlineData["mimeType"] as? String,
                   mimeType.contains("audio"),
                   let base64 = inlineData["data"] as? String {
                    audioPlayer.enqueue(base64PCM16Chunk: base64)
                }
            }
        }

        if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
            isResponding = false
            onModelTranscriptUpdate?(currentTranscript, true)
        }
    }
}

private final class PCM16StreamPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false)

    init() {
        guard let format else { return }
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    func enqueue(base64PCM16Chunk: String) {
        guard let format,
              let data = Data(base64Encoded: base64PCM16Chunk),
              let buffer = pcmBuffer(from: data, format: format) else {
            return
        }

        do {
            try ensureEngineIsRunning()
            if !playerNode.isPlaying {
                playerNode.play()
            }
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        } catch {
            stopAndReset()
        }
    }

    func stopAndReset() {
        playerNode.stop()
        playerNode.reset()
        engine.stop()
    }

    private func ensureEngineIsRunning() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        if !engine.isRunning {
            try engine.start()
        }
    }

    private func pcmBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.int16ChannelData else {
            return nil
        }

        buffer.frameLength = frameCount
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            channelData[0].update(from: samples.baseAddress!, count: Int(frameCount))
        }
        return buffer
    }
}
