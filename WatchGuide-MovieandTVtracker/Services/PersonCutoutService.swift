//
//  PersonCutoutService.swift
//  WatchGuide-MovieandTVtracker
//
//  Lifts the person out of a TMDB profile photo so it can sit on the page
//  with a transparent background.
//

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

actor PersonCutoutService {
    static let shared = PersonCutoutService()

    private var memoryCache: [String: CGImage] = [:]
    /// Paths Vision couldn't separate, so we don't retry them every visit.
    private var failedPaths: Set<String> = []
    private let ciContext = CIContext()

    private lazy var diskDirectory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches.appendingPathComponent("PersonCutouts-v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    /// Returns the photo with everything but the person made transparent, or
    /// nil when no clear subject is found (the caller shows the plain photo).
    func cutout(forProfilePath path: String) async -> CGImage? {
        if let cached = memoryCache[path] { return cached }
        if failedPaths.contains(path) { return nil }

        if let fileURL = diskURL(for: path),
           let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            memoryCache[path] = image
            return image
        }

        guard let url = TMDBService.shared.imageURL(path: path, size: .profile),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let photo = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cutout = makeCutout(of: photo) else {
            failedPaths.insert(path)
            return nil
        }

        memoryCache[path] = cutout
        if let fileURL = diskURL(for: path),
           let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cutout, nil)
            CGImageDestinationFinalize(destination)
        }
        return cutout
    }

    private func makeCutout(of photo: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: photo)
        do {
            try handler.perform([request])
        } catch {
            // Expected on the Simulator, which lacks the Neural Engine model.
            print("Person cutout failed: \(error)")
            return nil
        }

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty,
              let buffer = try? observation.generateMaskedImage(
                  ofInstances: observation.allInstances,
                  from: handler,
                  croppedToInstancesExtent: true
              ) else { return nil }

        let image = CIImage(cvPixelBuffer: buffer)
        guard let subject = ciContext.createCGImage(image, from: image.extent) else { return nil }
        return framedAsProfile(subject)
    }

    /// Places the subject on a square canvas like a profile picture: head near
    /// the top with a little headroom, shoulders filling the width. Centering
    /// the original 2:3 photo instead is what cut the tops of heads off.
    private func framedAsProfile(_ subject: CGImage) -> CGImage? {
        let width = CGFloat(subject.width)
        let height = CGFloat(subject.height)
        let headroom = width * 0.08
        let side = (width * 1.16).rounded()

        guard let context = CGContext(
            data: nil,
            width: Int(side),
            height: Int(side),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Core Graphics' origin is bottom-left. A tall subject hangs from the
        // top so the bottom crops off; a short one is centered.
        let y = height > side - headroom ? side - headroom - height : (side - height) / 2
        context.draw(subject, in: CGRect(x: (side - width) / 2, y: y, width: width, height: height))
        return context.makeImage()
    }

    private func diskURL(for path: String) -> URL? {
        let name = path.replacingOccurrences(of: "/", with: "")
        return diskDirectory?.appendingPathComponent(name).appendingPathExtension("png")
    }
}
