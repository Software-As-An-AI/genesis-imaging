import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Line Art Enhance — luminance level mapping (Photoshop "Levels" tool).
///
/// v0.3.4.1: median 3×3 removed after empirical test on Nadezhda's
/// reference image (`Tests/.../LineArtEnhanceEmpiricalTest.swift`)
/// proved median net-negative — it grew the halo zone (8.32% → 9.49%)
/// because grey edge pixels get reassigned to neighbor majority. Levels-only
/// path: halo 8.32% → 4.16%, extremes 21.75% → 93.17%. Cleaner result + 10×
/// faster (~0.1s vs ~2-3s).
///
/// Algorithm — single stage:
///
/// **Luminance level mapping (LUT-based):**
/// - pixel ≤ `darkCutoff`  → 0   (push to pure black)
/// - pixel ≥ `lightCutoff` → 255 (push to pure white)
/// - between               → linear stretch (preserve anti-alias gradient)
///
/// Mimics Photoshop "Levels" tool. Halo (mid-luminance grey clusters)
/// collapses to extremes; real anti-alias gradient at line edges stays
/// linearly stretched so curves remain smooth.
///
/// 3 calibrated presets (`LineArtEnhancePreset`): soft / normal / strong.
/// Tradeoff: tighter levels → more halo removal but more anti-alias loss.
/// Aggressiveness preset for `LineArtEnhanceFilter`. Controls how tightly
/// the luminance level mapping pushes mid-grey pixels to extremes.
///
/// Calibration (2026-05-16) — empirical histogram test on Nadezhda's
/// basketball comic reference (1254×1254). Halo zone = % pixels in [60-220]:
///
/// | Preset  | (dark, light) | Halo after | Extremes after |
/// |---------|---------------|------------|----------------|
/// | Baseline (no enhance) | —     | 8.32% | 21.75% |
/// | Yumuşak | (60, 220)     | ~5.5% | ~88%   |
/// | Normal  | (80, 180)     | ~3.3% | ~94.6% |
/// | Agresif | (100, 160)    | ~1.8% | ~97%   |
public enum LineArtEnhancePreset: String, CaseIterable, Codable, Sendable {
    case soft   = "soft"
    case normal = "normal"   // default, empirical sweet spot
    case strong = "strong"

    public var parameters: LineArtEnhanceFilter.Parameters {
        switch self {
        case .soft:   return .init(darkCutoff: 60,  lightCutoff: 220)
        case .normal: return .init(darkCutoff: 80,  lightCutoff: 180)
        case .strong: return .init(darkCutoff: 100, lightCutoff: 160)
        }
    }

    public var label: String {
        switch self {
        case .soft:   return "Yumuşak — anti-alias preserve"
        case .normal: return "Normal — dengeli (önerilen)"
        case .strong: return "Agresif — max temizlik, çizgi sertleşir"
        }
    }

    public var hint: String {
        switch self {
        case .soft:   return "Hafif halo bastırma, çizgi yumuşaklığı korunur"
        case .normal: return "Empirical optimal: halo %3'e iner, anti-alias muhafaza"
        case .strong: return "Maksimum halo temizliği, anti-alias kayıp olur"
        }
    }

    public static func from(rawValue: String) -> LineArtEnhancePreset {
        LineArtEnhancePreset(rawValue: rawValue) ?? .normal
    }
}

public enum LineArtEnhanceFilter {

    public enum FilterError: Error {
        case decodeFailed(URL)
        case encodeFailed(URL)
        case bufferAllocationFailed
    }

    /// `darkCutoff` / `lightCutoff` are absolute 0-255 luminance values:
    /// the linear stretch maps `(darkCutoff, lightCutoff)` → `(0, 255)`,
    /// with values below/above the cutoffs clamped to the extremes.
    public struct Parameters: Sendable {
        public let darkCutoff: UInt8
        public let lightCutoff: UInt8

        public static let `default` = Parameters(darkCutoff: 80, lightCutoff: 180)
    }

    /// Apply enhancement in-place: read PNG at `url`, write the enhanced
    /// version back to the same URL via temp + atomic rename.
    public static func apply(
        url: URL,
        parameters: Parameters = .default
    ) throws {
        // 1. Decode PNG → CGImage
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw FilterError.decodeFailed(url)
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width

        // 2. Render to 8-bit grayscale buffer
        var pixels = [UInt8](repeating: 0, count: width * height)
        // Same colorspace for decode + encode to avoid gamma shift; see
        // EraserSession.load for the customer-reported smudge symptom.
        guard let cs = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
            ?? CGColorSpaceCreateDeviceGray() as CGColorSpace?
        else { throw FilterError.bufferAllocationFailed }

        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        guard let ctx = pixels.withUnsafeMutableBufferPointer({ buf -> CGContext? in
            CGContext(
                data: buf.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        }) else { throw FilterError.bufferAllocationFailed }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 3. Apply enhancement on the grayscale buffer
        applyOnGrayscale(
            buffer: &pixels,
            width: width, height: height,
            parameters: parameters
        )

        // 4. Re-encode as PNG
        try encodeGrayscalePNG(
            buffer: pixels,
            width: width, height: height,
            to: url
        )
    }

    /// Public for unit testing — operate directly on a grayscale buffer.
    /// Level mapping only (median dropped in v0.3.4.1, empirically net-negative).
    static func applyOnGrayscale(
        buffer: inout [UInt8],
        width: Int, height: Int,
        parameters: Parameters
    ) {
        applyLevelsInPlace(
            buffer: &buffer,
            darkCutoff: parameters.darkCutoff,
            lightCutoff: parameters.lightCutoff
        )
    }

    /// Replace each pixel with the median of its 3×3 neighborhood. Edge
    /// pixels (first/last row + col) are left unchanged — the cost of
    /// proper edge handling on line art is negligible (1-px border).
    ///
    /// In-place via a single auxiliary output buffer; runtime O(n) with
    /// constant-factor 9-element sort per pixel. Apple-pure Swift, no
    /// framework dependencies beyond Foundation.
    static func median3x3InPlace(
        buffer: inout [UInt8],
        width: Int, height: Int
    ) {
        precondition(buffer.count == width * height)
        if width < 3 || height < 3 { return }
        var out = buffer

        for y in 1..<(height - 1) {
            let rowAbove = (y - 1) * width
            let rowMid   =  y * width
            let rowBelow = (y + 1) * width
            for x in 1..<(width - 1) {
                // Collect the 9 neighbors into a fixed-size array.
                var n: [UInt8] = [
                    buffer[rowAbove + (x - 1)], buffer[rowAbove + x], buffer[rowAbove + (x + 1)],
                    buffer[rowMid   + (x - 1)], buffer[rowMid   + x], buffer[rowMid   + (x + 1)],
                    buffer[rowBelow + (x - 1)], buffer[rowBelow + x], buffer[rowBelow + (x + 1)],
                ]
                // Median = 5th element after sort (0-indexed: index 4).
                n.sort()
                out[rowMid + x] = n[4]
            }
        }
        buffer = out
    }

    /// Push pixels below `darkCutoff` to 0, above `lightCutoff` to 255,
    /// and linearly stretch the in-between range. Preserves anti-aliasing
    /// at edges while flattening the halo region.
    static func applyLevelsInPlace(
        buffer: inout [UInt8],
        darkCutoff: UInt8,
        lightCutoff: UInt8
    ) {
        precondition(lightCutoff > darkCutoff, "lightCutoff must exceed darkCutoff")
        let range = Int(lightCutoff) - Int(darkCutoff)
        // Lookup table for O(1) per-pixel transform.
        var lut = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            if i <= Int(darkCutoff) {
                lut[i] = 0
            } else if i >= Int(lightCutoff) {
                lut[i] = 255
            } else {
                // Linear stretch (i - dark) / range × 255
                let mapped = ((i - Int(darkCutoff)) * 255 + range / 2) / range
                lut[i] = UInt8(clamping: mapped)
            }
        }
        for i in 0..<buffer.count {
            buffer[i] = lut[Int(buffer[i])]
        }
    }

    // MARK: - PNG encode helper

    private static func encodeGrayscalePNG(
        buffer: [UInt8],
        width: Int, height: Int,
        to url: URL
    ) throws {
        let cs = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
            ?? CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        let bytesPerRow = width
        guard let provider = CGDataProvider(data: Data(buffer) as CFData) else {
            throw FilterError.encodeFailed(url)
        }
        guard let cgImage = CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { throw FilterError.encodeFailed(url) }

        guard let dst = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw FilterError.encodeFailed(url) }

        CGImageDestinationAddImage(dst, cgImage, nil)
        guard CGImageDestinationFinalize(dst) else {
            throw FilterError.encodeFailed(url)
        }
    }
}
