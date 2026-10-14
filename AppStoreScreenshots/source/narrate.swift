// Renders a line of narration to an audio file with a system voice (e.g. the Siri natural voices).
// Usage: swiftc -O narrate.swift -o ../tools/narrate && ../tools/narrate <voice-id> <out.caf> "<text>" [rate]
// List voice ids: AVSpeechSynthesisVoice.speechVoices(), e.g. com.apple.siri.natural.Simone.
import AVFoundation

let args = CommandLine.arguments
let voiceID = args[1], outURL = URL(fileURLWithPath: args[2]), text = args[3]
let rate = args.count > 4 ? Float(args[4])! : AVSpeechUtteranceDefaultSpeechRate

// Siri voices only resolve from the full list, not from AVSpeechSynthesisVoice(identifier:).
guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.identifier == voiceID })
        ?? AVSpeechSynthesisVoice(identifier: voiceID) else {
    FileHandle.standardError.write("No voice \(voiceID)\n".data(using: .utf8)!); exit(1)
}
let utterance = AVSpeechUtterance(string: text)
utterance.voice = voice
utterance.rate = rate

let synth = AVSpeechSynthesizer()
var file: AVAudioFile?
var finished = false
synth.write(utterance) { buffer in
    guard let pcm = buffer as? AVAudioPCMBuffer else { return }
    if pcm.frameLength == 0 { finished = true; return }   // an empty buffer marks the end
    if file == nil { file = try! AVAudioFile(forWriting: outURL, settings: pcm.format.settings) }
    try! file!.write(from: pcm)
}
while !finished { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
print(String(format: "%.2f", Double(file?.length ?? 0) / (file?.processingFormat.sampleRate ?? 1)))
