import SwiftUI

// A container that renders an animated ambient layer behind the hero carousel.
// It approximates trailer-reactive lighting by animating between colors derived
// from the trailer's YouTube thumbnail (if available) and the item's backdrop.
struct HeroAmbientContainer: View {
    let items: [MediaItem]
    let onItemTap: (MediaItem) -> Void

    // Animation state
    @State private var palette: [Color] = [.black, .black]
    @State private var currentIndex: Int = 0
    @State private var nextIndex: Int = 1
    @State private var phase: CGFloat = 0.0
    @State private var timer: Timer?

    // Controls
    var cycleDuration: TimeInterval = 3.0
    var intensity: Double = 0.6

    var body: some View {
        ZStack {
            // Ambient animated background
            AnimatedAmbientBackground(colors: palette, intensity: intensity, phase: phase)
                .ignoresSafeArea()

            // Existing hero carousel
            HeroCarouselView(items: items, onItemTap: onItemTap)
                .onChange(of: items.first?.id) { _, _ in
                    // Reset when items change
                    buildInitialPalette()
                }
        }
        .onAppear {
            buildInitialPalette()
            startCycling()
        }
        .onDisappear {
            stopCycling()
        }
    }

    private func startCycling() {
        stopCycling()
        timer = Timer.scheduledTimer(withTimeInterval: cycleDuration, repeats: true) { _ in
            withAnimation(.easeInOut(duration: cycleDuration)) {
                phase = (phase + 1).truncatingRemainder(dividingBy: 1000)
                // Rotate palette indices to create motion
                if palette.count > 1 {
                    currentIndex = (currentIndex + 1) % palette.count
                    nextIndex = (currentIndex + 1) % palette.count
                }
            }
        }
    }

    private func stopCycling() {
        timer?.invalidate()
        timer = nil
    }

    // Build an initial palette from the first item's trailer thumbnail and backdrop
    private func buildInitialPalette() {
        guard let first = items.first else {
            palette = [.black, .black]
            return
        }

        // Attempt to fetch the trailer thumbnail using known YouTube patterns if we can resolve a key later.
        // As we don't have direct access to the trailer key here, we approximate with the backdrop image.
        // You can enhance this by passing in a [Int: String] map of mediaId -> trailerKey to fetch the thumbnail.
        if let path = first.backdropPath, let url = TMDBService.shared.imageURL(path: path, size: .backdrop) {
            Task {
                if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                    let colors = ui.dominantPalette(maxColors: 4)
                    await MainActor.run {
                        palette = colors.map { Color($0) }
                        if palette.isEmpty { palette = [.black, .black] }
                    }
                } else {
                    await MainActor.run { palette = [.black, .black] }
                }
            }
        } else {
            palette = [.black, .black]
        }
    }
}

// Animated ambient background that blends between multiple colors
struct AnimatedAmbientBackground: View {
    let colors: [Color]
    var intensity: Double
    var phase: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base fill
                (colors.first ?? .black).opacity(intensity * 0.6)

                // Overlapping radial gradients for motion
                ForEach(0..<(max(colors.count, 2)), id: \.self) { idx in
                    let color = colors[safe: idx] ?? .black
                    let radius = max(geo.size.width, geo.size.height) * (0.6 + 0.2 * CGFloat((idx % 3)))
                    let offsetX = sin(phase + CGFloat(idx)) * geo.size.width * 0.15
                    let offsetY = cos(phase * 0.8 + CGFloat(idx)) * geo.size.height * 0.15

                    RadialGradient(colors: [color.opacity(intensity), color.opacity(0.0)], center: .center, startRadius: 0, endRadius: radius)
                        .blendMode(.plusLighter)
                        .offset(x: offsetX, y: offsetY)
                }
            }
            .blur(radius: 80)
            .background(Color.black)
        }
    }
}

// MARK: - Helpers
// Note: Array safe subscript is defined in HeroCarouselView.swift

extension UIImage {
    // Average color as a fallback
    func averageColor() -> UIColor? {
        guard let inputImage = CIImage(image: self) else { return nil }
        let extent = inputImage.extent
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: CIVector(cgRect: extent)])
        guard let outputImage = filter?.outputImage else { return nil }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(bitmap[0]) / 255.0, green: CGFloat(bitmap[1]) / 255.0, blue: CGFloat(bitmap[2]) / 255.0, alpha: 1)
    }

    // Lightweight dominant palette: sample a grid and pick top hues
    func dominantPalette(maxColors: Int = 4) -> [UIColor] {
        // Downscale for speed
        let targetSize = CGSize(width: 64, height: 64)
        UIGraphicsBeginImageContextWithOptions(targetSize, true, 0)
        draw(in: CGRect(origin: .zero, size: targetSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        guard let img = resized, let cg = img.cgImage else {
            if let avg = averageColor() { return [avg] }
            return []
        }

        // Sample pixels
        guard let data = cg.dataProvider?.data as Data? else {
            if let avg = averageColor() { return [avg] }
            return []
        }
        let bytes = [UInt8](data)
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]

        let step = 4
        var i = 0
        while i + 3 < bytes.count {
            let r = Int(bytes[i])
            let g = Int(bytes[i+1])
            let b = Int(bytes[i+2])
            // Quantize to reduce unique keys
            let qr = r / 24
            let qg = g / 24
            let qb = b / 24
            let key = (qr << 16) | (qg << 8) | qb
            var entry = buckets[key] ?? (0,0,0,0)
            entry.count += 1
            entry.r += r
            entry.g += g
            entry.b += b
            buckets[key] = entry
            i += step
        }

        // Pick top buckets by count
        let sorted = buckets.sorted { $0.value.count > $1.value.count }
        let top = sorted.prefix(maxColors)
        let colors: [UIColor] = top.map { _, v in
            let c = max(v.count, 1)
            return UIColor(red: CGFloat(v.r / c) / 255.0, green: CGFloat(v.g / c) / 255.0, blue: CGFloat(v.b / c) / 255.0, alpha: 1)
        }
        return colors
    }
}
