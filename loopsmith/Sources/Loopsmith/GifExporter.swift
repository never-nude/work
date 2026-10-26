import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct GifSettings {
    var start: Double
    var end: Double
    var fps: Int
    var width: Int
    var height: Int
    var speed: Double
    var boomerang: Bool

    /// Number of frames that will be written, including the boomerang return trip.
    var frameCount: Int {
        let forward = max(1, Int(((end - start) / speed * Double(fps)).rounded(.down)))
        return boomerang ? forward * 2 - 2 : forward
    }
}

enum GifExporter {
    /// Renders the selected range of `asset` to an animated GIF at `url`.
    /// Returns the number of frames written.
    static func export(
        asset: AVAsset,
        settings: GifSettings,
        to url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int {
        let forwardCount = max(1, Int(((settings.end - settings.start) / settings.speed * Double(settings.fps)).rounded(.down)))
        let totalCount = settings.frameCount
        let frameDuration = 1.0 / Double(settings.fps)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: settings.width, height: settings.height)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 120)

        let times: [CMTime] = (0..<forwardCount).map { index in
            let seconds = settings.start + Double(index) * settings.speed / Double(settings.fps)
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }

        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, totalCount, nil
        ) else {
            throw LoopsmithError.gifCreateFailed
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDuration,
                kCGImagePropertyGIFUnclampedDelayTime: frameDuration,
            ]
        ]
        let frameDict = frameProperties as CFDictionary

        var written = 0
        var backlog: [CGImage] = []

        for await result in generator.images(for: times) {
            switch result {
            case .success(_, let image, _):
                CGImageDestinationAddImage(destination, image, frameDict)
                written += 1
                if settings.boomerang {
                    backlog.append(image)
                }
                progress(Double(written) / Double(max(totalCount, 1)))
            case .failure:
                continue
            }
        }

        if settings.boomerang, backlog.count > 2 {
            // Play back toward the start, skipping the two endpoints so the loop doesn't stutter.
            for image in backlog.dropFirst().dropLast().reversed() {
                CGImageDestinationAddImage(destination, image, frameDict)
                written += 1
                progress(Double(written) / Double(max(totalCount, 1)))
            }
        }

        guard written > 0 else {
            throw LoopsmithError.noFrames
        }
        guard CGImageDestinationFinalize(destination) else {
            throw LoopsmithError.gifFinalizeFailed
        }
        return written
    }
}
