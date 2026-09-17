//
//  AtlasVoiceAudioIO.swift
//  WatchGuide-MovieandTVtracker
//
//  Real-time audio capture and playback for Ask Atlas voice mode.
//
//  Captures microphone audio and downsamples it to the 16 kHz signed-16-bit
//  PCM the Gemini Live API expects, and plays back the 24 kHz signed-16-bit
//  PCM the model returns. Hardware voice processing provides echo cancellation
//  so the model doesn't transcribe its own speech.
//
//  iOS-only: relies on AVAudioSession, which isn't available on macOS.
//

import Foundation
import AVFoundation

#if os(iOS)
final class AtlasVoiceAudioIO {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var converter: AVAudioConverter?

    /// Mic capture is converted to this format before sending to Gemini.
    private let captureFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
    )!
    /// Gemini returns 24 kHz PCM16; we play it back as float for the mixer.
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false
    )!

    private var onMicChunk: ((Data) -> Void)?
    /// Reports a 0...1 mic input level (~per buffer) for the UI meter.
    private var onMicLevel: ((Float) -> Void)?
    private(set) var isRunning = false
    private var isMuted = false

    /// When Atlas is playing audio back, we stop *sending* mic audio so the
    /// model never hears its own voice (half-duplex — we have no hardware echo
    /// cancellation). Tracks the wall-clock time playback is expected to finish.
    private var scheduledPlaybackEnd = Date.distantPast
    private let playbackTailMargin: TimeInterval = 0.35   // grace after audio ends
    private var levelCounter = 0   // throttles mic-level UI updates

    #if DEBUG
    private var debugBufferCount = 0
    private var debugBytesSent = 0
    #endif

    // MARK: - Lifecycle

    /// Starts the audio session and engine. `onMicChunk` is called on the audio
    /// thread with little-endian 16 kHz PCM16 mono data ready to send.
    func start(onMicChunk: @escaping (Data) -> Void, onMicLevel: ((Float) -> Void)? = nil) throws {
        guard !isRunning else { return }
        self.onMicChunk = onMicChunk
        self.onMicLevel = onMicLevel

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: [])

        let input = engine.inputNode
        // NOTE: setVoiceProcessingEnabled(true) (hardware AEC) is known to stop
        // the input tap from delivering buffers in some configs / on Simulator.
        // Disabled for now so capture is reliable; revisit AEC later if the
        // model hears its own playback.
        // try? input.setVoiceProcessingEnabled(true)

        // Read the input format AFTER enabling voice processing and activating
        // the session, so the sample rate is settled (not 0).
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "AtlasVoiceAudioIO", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone input format unavailable (sampleRate 0). The device may have no usable mic input."])
        }
        converter = AVAudioConverter(from: inputFormat, to: captureFormat)

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)

        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.handleMicBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        playerNode.play()
        isRunning = true

        #if DEBUG
        print("AtlasVoice mic started — input \(inputFormat.sampleRate)Hz, ch=\(inputFormat.channelCount), converter=\(converter != nil)")
        #endif
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isRunning = false
        onMicChunk = nil
        scheduledPlaybackEnd = .distantPast
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    /// Drops any queued/playing audio — used when the user barges in and the
    /// server reports the model turn was interrupted.
    func flushPlayback() {
        guard isRunning else { return }
        playerNode.stop()
        playerNode.play()
        scheduledPlaybackEnd = .distantPast   // let the mic resume immediately
    }

    // MARK: - Capture

    private func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
        #if DEBUG
        debugBufferCount += 1
        if debugBufferCount <= 3 {
            print("AtlasVoice TAP fired #\(debugBufferCount): inFrames=\(buffer.frameLength) fmt=\(buffer.format.sampleRate)Hz/\(buffer.format.channelCount)ch")
        }
        #endif
        guard !isMuted, let converter, let onMicChunk else { return }

        let ratio = captureFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity) else { return }

        var fedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if fedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, output.frameLength > 0, let channel = output.int16ChannelData else {
            #if DEBUG
            if let conversionError { print("AtlasVoice convert error: \(conversionError.localizedDescription)") }
            #endif
            return
        }
        let frameCount = Int(output.frameLength)
        let samples = channel[0]
        let data = Data(bytes: samples, count: frameCount * MemoryLayout<Int16>.size)

        // Compute a rough RMS level (0...1) for the UI meter — throttled to
        // roughly every 3rd buffer (~8/sec) to avoid excessive UI re-renders.
        levelCounter &+= 1
        if let onMicLevel, levelCounter % 3 == 0 {
            var sum: Double = 0
            for i in 0..<frameCount {
                let v = Double(samples[i]) / 32_768.0
                sum += v * v
            }
            let rms = frameCount > 0 ? (sum / Double(frameCount)).squareRoot() : 0
            let level = Float(min(1.0, rms * 4.0))   // scale up; speech RMS is small
            onMicLevel(level)
        }

        // Half-duplex: while Atlas is speaking (and a short tail after), don't
        // send mic audio — otherwise the model hears its own playback / picks up
        // the room while talking. The level meter above still runs.
        if Date() < scheduledPlaybackEnd.addingTimeInterval(playbackTailMargin) {
            return
        }

        #if DEBUG
        debugBytesSent += data.count
        if debugBufferCount % 25 == 0 {
            print("AtlasVoice mic: \(debugBufferCount) buffers tapped, \(debugBytesSent) bytes sent so far")
        }
        #endif

        onMicChunk(data)
    }

    // MARK: - Playback

    /// Enqueues little-endian 24 kHz PCM16 mono audio from Gemini for playback.
    func enqueuePlayback(pcm16Data: Data) {
        guard isRunning, !pcm16Data.isEmpty else { return }
        let frameCount = pcm16Data.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frameCount)),
              let floatChannel = buffer.floatChannelData else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        pcm16Data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            let destination = floatChannel[0]
            for index in 0..<frameCount {
                destination[index] = Float(Int16(littleEndian: samples[index])) / 32_768.0
            }
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }

        // Extend the expected playback-end time so the mic stays gated for the
        // full duration of everything queued (chunks arrive faster than realtime).
        let duration = Double(frameCount) / playbackFormat.sampleRate
        let now = Date()
        scheduledPlaybackEnd = max(now, scheduledPlaybackEnd).addingTimeInterval(duration)
    }
}
#endif
