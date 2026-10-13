// Puts a soundtrack on a rendered video: the video track of <video.mp4> plus the audio of
// <audio.m4a>, trimmed to the video's length, written to <out.mp4> without re-encoding.
// Usage: swift mux.swift <video.mp4> <audio.m4a> <out.mp4>
import AVFoundation

let args = CommandLine.arguments
let video = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let audio = AVURLAsset(url: URL(fileURLWithPath: args[2]))
let outURL = URL(fileURLWithPath: args[3])

let sema = DispatchSemaphore(value: 0)
Task {
    let comp = AVMutableComposition()
    let duration = try await video.load(.duration)
    let range = CMTimeRange(start: .zero, duration: duration)
    let vSrc = try await video.loadTracks(withMediaType: .video).first!
    let aSrc = try await audio.loadTracks(withMediaType: .audio).first!
    let v = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try v.insertTimeRange(range, of: vSrc, at: .zero)
    let aDuration = try await audio.load(.duration)
    let a = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try a.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, aDuration)), of: aSrc, at: .zero)

    try? FileManager.default.removeItem(at: outURL)
    let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
    try await export.export(to: outURL, as: .mp4)
    print("wrote \(outURL.path) (\(String(format: "%.1f", CMTimeGetSeconds(duration))) s)")
    sema.signal()
}
sema.wait()
