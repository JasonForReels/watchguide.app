// Encodes a folder of frames (f00000.jpg …) into an App Preview .mp4: H.264 + silent stereo AAC.
// Usage: swiftc -O encode.swift -o encode && ./encode <frames-dir> <out.mp4> [fps]
import AVFoundation
import AppKit

let args = CommandLine.arguments
let dir = args[1], outURL = URL(fileURLWithPath: args[2])
let fps = Int32(args.count > 3 ? Int(args[3])! : 30)
let files = try! FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasPrefix("f") }.sorted()
let first = NSImage(contentsOfFile: "\(dir)/\(files[0])")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let W = first.width, H = first.height

try? FileManager.default.removeItem(at: outURL)
let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mp4)
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 14_000_000,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000])
writer.add(vIn); writer.add(aIn)
writer.startWriting(); writer.startSession(atSourceTime: .zero)

var asbd = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 4,
    mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
var fmt: CMAudioFormatDescription?
CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                               magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)
var written = 0
// Audio and video must be interleaved, or the writer stalls waiting for the other track.
func appendSilence(upTo target: Int) {
    while written < target && aIn.isReadyForMoreMediaData {
        let n = min(4410, target - written)
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n * 4, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: n * 4, flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &block)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block!, offsetIntoDestination: 0, dataLength: n * 4)
        var sb: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: fmt!,
            sampleCount: n, presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: 44100),
            packetDescriptions: nil, sampleBufferOut: &sb)
        aIn.append(sb!); written += n
    }
}

for (i, f) in files.enumerated() {
    let t = Double(i) / Double(fps)
    appendSilence(upTo: Int((t + 0.5) * 44100))
    while !vIn.isReadyForMoreMediaData { appendSilence(upTo: Int((t + 1.0) * 44100)); usleep(500) }
    let img = NSImage(contentsOfFile: "\(dir)/\(f)")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
}
vIn.markAsFinished()
let total = Int(Double(files.count) / Double(fps) * 44100)
while written < total { appendSilence(upTo: total); usleep(500) }
aIn.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "wrote \(files.count) frames, \(W)x\(H)" : "failed: \(String(describing: writer.error))")
