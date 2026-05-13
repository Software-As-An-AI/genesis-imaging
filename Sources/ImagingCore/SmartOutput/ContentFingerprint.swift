import Foundation
import ImageIO
import CoreGraphics

/// Rich content classification for a PNG file. Computed in a single pixel-
/// sampling pass (stride 8, matching `ContentDetector.analyze`). Used by
/// `ContentClassifier.pickAdaptiveMode` to route content to the best
/// aggressive compression mode.
///
/// **Empirical calibration (2026-05-13 Phuket, 4 customer coloring books):**
/// - Pure B/W coloring book content: nearBinary 0.88-0.93, saturation < 0.01,
///   edgeDensity 0.14-0.19, unique 23K-30K (after ncnn 4× anti-aliasing).
/// - Plan v2 decision tree thresholds derived from this calibration.
public struct ContentFingerprint: Sendable, Equatable {
    /// Sampled unique RGB triplets (same as `ContentDetector.Analysis.uniqueColorCount`).
    public let uniqueColorCount: Int

    /// Fraction of sampled pixels with luminance near 0 (< 30) or near 255 (> 225).
    /// Range 0.0-1.0. Customer coloring books measure 0.85-0.95.
    public let nearBinaryScore: Double

    /// Average per-pixel saturation (max channel − min channel, normalized).
    /// Range 0.0-1.0. B/W ≈ 0.0; vibrant color photo ≈ 0.3-0.6.
    public let saturationScore: Double

    /// Fraction of vertically-adjacent sample pairs with |Δluminance| > 50.
    /// Range 0.0-1.0. Higher = more line art / detail; lower = solid regions.
    public let edgeDensityScore: Double

    /// Total samples used to compute the above (diagnostic; not used in decisions).
    public let sampledPixels: Int

    public init(
        uniqueColorCount: Int,
        nearBinaryScore: Double,
        saturationScore: Double,
        edgeDensityScore: Double,
        sampledPixels: Int
    ) {
        self.uniqueColorCount = uniqueColorCount
        self.nearBinaryScore = nearBinaryScore
        self.saturationScore = saturationScore
        self.edgeDensityScore = edgeDensityScore
        self.sampledPixels = sampledPixels
    }
}

public enum ContentClassifier {
    /// Sampling stride — every 8th pixel both axes. Matches `ContentDetector`
    /// so callers can rely on similar performance characteristics.
    public static let sampleStride = 8

    /// Luminance bands defining "near-binary" pixels.
    static let lumNearBlack: Int = 30
    static let lumNearWhite: Int = 225

    /// Neighbor luminance delta threshold for edge detection.
    static let edgeDeltaThreshold: Int = 50

    /// Compute the full fingerprint for `pngURL`. Returns `nil` on decode failure.
    /// Single rasterization pass, ~10-50ms for 8192×8192 image.
    public static func fingerprint(pngURL: URL) -> ContentFingerprint? {
        guard let source = CGImageSourceCreateWithURL(pngURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let cs = CGColorSpaceCreateDeviceRGB()
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = buffer.withUnsafeMutableBytes({ ptr -> CGContext? in
            guard let base = ptr.baseAddress else { return nil }
            return CGContext(
                data: base,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Single-pass sample. Read every 8th pixel in row-major order; for
        // edge density we compare each sample to the same-column sample
        // from the previous sampled row.
        var uniqueColors = Set<UInt32>()
        var nearBinaryCount = 0
        var saturationTotal = 0
        var edgeCount = 0
        var sampleCount = 0

        // Previous row's luminance values, indexed by column-sample-index.
        let columnsSampled = (width + Self.sampleStride - 1) / Self.sampleStride
        var prevRowLum = [Int](repeating: -1, count: columnsSampled)
        var hasPrevRow = false

        for y in Swift.stride(from: 0, to: height, by: Self.sampleStride) {
            var colIdx = 0
            for x in Swift.stride(from: 0, to: width, by: Self.sampleStride) {
                let off = y * bytesPerRow + x * bytesPerPixel
                let r = Int(buffer[off])
                let g = Int(buffer[off + 1])
                let b = Int(buffer[off + 2])
                let packed = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
                uniqueColors.insert(packed)

                let lum = (r + g + b) / 3
                if lum < Self.lumNearBlack || lum > Self.lumNearWhite {
                    nearBinaryCount += 1
                }
                saturationTotal += max(r, g, b) - min(r, g, b)

                if hasPrevRow, colIdx < prevRowLum.count {
                    let prev = prevRowLum[colIdx]
                    if prev >= 0, abs(lum - prev) > Self.edgeDeltaThreshold {
                        edgeCount += 1
                    }
                }
                if colIdx < prevRowLum.count {
                    prevRowLum[colIdx] = lum
                }
                colIdx += 1
                sampleCount += 1
            }
            hasPrevRow = true
        }

        guard sampleCount > 0 else { return nil }
        return ContentFingerprint(
            uniqueColorCount: uniqueColors.count,
            nearBinaryScore: Double(nearBinaryCount) / Double(sampleCount),
            saturationScore: Double(saturationTotal) / Double(sampleCount) / 255.0,
            edgeDensityScore: Double(edgeCount) / Double(sampleCount),
            sampledPixels: sampleCount
        )
    }

    /// Decide which Smart Output mode best matches `fingerprint`. Returns one of:
    /// `.binarize`, `.colors8` (lineart), `.colors32`, `.softLoss`, `.auto` (lossless).
    ///
    /// **Decision tree (empirically calibrated 2026-05-13 vs 4 customer files):**
    ///
    /// 1. **Coloring book path** (nearBinary > 0.85, saturation < 0.05):
    ///    - High edge density (> 0.15) → `.colors8` (preserve smooth anti-aliasing)
    ///    - Low edge density → `.binarize` (pure B/W, max compression)
    /// 2. **Cartoon/limited palette** (unique < 8192, saturation < 0.5) → `.colors32`
    /// 3. **Low-mid entropy** (unique < 65536) → `.softLoss`
    /// 4. **Photo / continuous tone** → `.auto` (lossless oxipng path)
    public static func pickAdaptiveMode(fingerprint: ContentFingerprint) -> SmartOutputMode {
        // Coloring book / B/W line art branch.
        if fingerprint.nearBinaryScore > 0.85 && fingerprint.saturationScore < 0.05 {
            if fingerprint.edgeDensityScore > 0.15 {
                return .colors8   // lineart — preserve anti-aliasing
            } else {
                return .binarize  // pure B/W — max compression
            }
        }

        // Limited-palette cartoon / comic / UI.
        if fingerprint.uniqueColorCount < 8192 && fingerprint.saturationScore < 0.5 {
            return .colors32
        }

        // Anti-aliased mid-entropy content (ncnn-upscaled illustrations).
        if fingerprint.uniqueColorCount < 65536 {
            return .softLoss
        }

        // Photo / continuous tone — lossless preservation.
        return .auto
    }
}
