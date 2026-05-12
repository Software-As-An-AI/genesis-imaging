import Foundation
import ImageIO
import CoreGraphics

/// Fast, deterministic content-type heuristic for a PNG file.
///
/// Counts unique RGB values in a sampled grid (every 8th pixel both axes —
/// ~64× speedup over full scan, statistically robust for content
/// classification). No machine learning, no perceptual model — just enough
/// signal to distinguish "limited-palette content where pngquant is safe"
/// from "continuous-tone content where pngquant would degrade quality".
public enum ContentDetector {

    /// Threshold below which pngquant is considered safe-to-apply.
    /// pngquant produces 256-color palette PNG; if source already has ≤256
    /// unique colors, quantization is lossless (or nearly so for soft
    /// anti-aliasing).
    public static let lowEntropyThreshold = 256

    /// Result of analysis. Returned by `analyze(pngURL:)`.
    public struct Analysis: Sendable, Equatable {
        public let uniqueColorCount: Int
        public let sampledPixels: Int
        public let imageBytes: Int

        /// True iff `uniqueColorCount < lowEntropyThreshold`. Indicates
        /// the file is a quantization-safe candidate (line art / B/W /
        /// screenshot / UI mock / anime / comic).
        public let isLowEntropy: Bool

        public init(
            uniqueColorCount: Int,
            sampledPixels: Int,
            imageBytes: Int,
            isLowEntropy: Bool
        ) {
            self.uniqueColorCount = uniqueColorCount
            self.sampledPixels = sampledPixels
            self.imageBytes = imageBytes
            self.isLowEntropy = isLowEntropy
        }
    }

    /// Analyze the PNG at `pngURL`. Returns `nil` on any decode failure —
    /// callers treat `nil` as "unknown" and route through the conservative
    /// path (oxipng-only / skip).
    public static func analyze(pngURL: URL) -> Analysis? {
        let imageBytes = (try? FileManager.default.attributesOfItem(
            atPath: pngURL.path
        )[.size] as? Int) ?? 0

        guard let source = CGImageSourceCreateWithURL(pngURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        // Render into a known RGBA8 buffer so we can read bytes directly.
        // CoreGraphics handles colorspace conversion (e.g. P3, indexed, gray).
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = buffer.withUnsafeMutableBytes({ ptr -> CGContext? in
            guard let baseAddress = ptr.baseAddress else { return nil }
            return CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sample every 8th pixel on both axes (64× speedup, ~1.5% of pixels
        // for a 2048×2048 image = 65 536 samples — more than enough to hit
        // 256 unique colors if any exist).
        let stride = 8
        var uniqueColors = Set<UInt32>()
        var sampledCount = 0
        // Early-exit guard: once we exceed 2× threshold we can stop —
        // result is already "high entropy" with statistical certainty.
        let earlyExitCeiling = lowEntropyThreshold * 2

        for y in Swift.stride(from: 0, to: height, by: stride) {
            for x in Swift.stride(from: 0, to: width, by: stride) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = UInt32(buffer[offset])
                let g = UInt32(buffer[offset + 1])
                let b = UInt32(buffer[offset + 2])
                // Pack RGB into single UInt32 (ignore alpha — coloring books
                // don't carry alpha info we'd want to differentiate by).
                let packed = (r << 16) | (g << 8) | b
                uniqueColors.insert(packed)
                sampledCount += 1
                if uniqueColors.count > earlyExitCeiling {
                    return Analysis(
                        uniqueColorCount: uniqueColors.count,
                        sampledPixels: sampledCount,
                        imageBytes: imageBytes,
                        isLowEntropy: false
                    )
                }
            }
        }

        return Analysis(
            uniqueColorCount: uniqueColors.count,
            sampledPixels: sampledCount,
            imageBytes: imageBytes,
            isLowEntropy: uniqueColors.count < lowEntropyThreshold
        )
    }
}
