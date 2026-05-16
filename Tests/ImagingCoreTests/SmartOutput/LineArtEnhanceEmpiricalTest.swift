import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ImagingCore

/// Empirical histogram-based test against operator's real reference image:
/// `~/Downloads/image-dirty.png` (1254×1254 basketball comic). Measures
/// luminance distribution shift after various enhancement parameter sets.
///
/// Why histogram, not pixel diff: dirty/clean reference pair the operator
/// shared have different dimensions (1254² vs 1545×2000) — operator's manual
/// cleanup workflow involved canvas resize, so byte-level diff impossible.
/// Histogram movement (how much mid-grey halo gets pushed to extremes) is
/// the next-best objective metric.
///
/// Mid-range luminance = `[60, 220]` (halo zone). Pixels in this range are
/// the "soft halo" the algorithm targets. After enhance, this range should
/// shrink (pixels migrate to 0 or 255 extremes).
final class LineArtEnhanceEmpiricalTest: XCTestCase {

    private func loadGrayscale(_ url: URL) -> (buffer: [UInt8], width: Int, height: Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = cgImage.width
        let h = cgImage.height
        var buf = [UInt8](repeating: 0, count: w * h)
        guard let cs = CGColorSpace(name: CGColorSpace.linearGray)
                ?? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        else { return nil }
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        guard let ctx = buf.withUnsafeMutableBufferPointer({ bbuf -> CGContext? in
            CGContext(
                data: bbuf.baseAddress,
                width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w,
                space: cs,
                bitmapInfo: bitmapInfo
            )
        }) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (buf, w, h)
    }

    private func histogram(_ buf: [UInt8]) -> [Int] {
        var hist = [Int](repeating: 0, count: 256)
        for b in buf { hist[Int(b)] += 1 }
        return hist
    }

    /// Count pixels in [60, 220] — the "halo zone". Lower count = more
    /// pixels pushed to extremes (improvement).
    private func haloZoneCount(_ hist: [Int]) -> Int {
        return hist[60...220].reduce(0, +)
    }

    /// Count pixels at 0 (pure black) and 255 (pure white). Higher = more
    /// extreme content (good for line art).
    private func extremeCount(_ hist: [Int]) -> (black: Int, white: Int) {
        return (black: hist[0], white: hist[255])
    }

    func testEnhanceOnNadezhdaReferenceImage() throws {
        let dirtyURL = URL(fileURLWithPath: "/Users/okan.yucel/Downloads/image-dirty.png")
        guard FileManager.default.fileExists(atPath: dirtyURL.path) else {
            throw XCTSkip("Reference image not present — \(dirtyURL.path)")
        }
        guard let (originalBuf, w, h) = loadGrayscale(dirtyURL) else {
            XCTFail("Failed to decode reference"); return
        }
        let total = w * h
        let baseline = histogram(originalBuf)
        let baselineHalo = haloZoneCount(baseline)
        let baselineExt = extremeCount(baseline)

        print("")
        print("Line Art Enhance — Empirical Test on Nadezhda Reference")
        print("Image: \(w)×\(h) (\(total) pixels)")
        print("")
        print("Param Set                          | Halo zone [60-220]  | Extremes (0+255)")
        print("Baseline (no processing)           | \(baselineHalo) (\(pct(baselineHalo, total)))  | \(baselineExt.black + baselineExt.white) (\(pct(baselineExt.black + baselineExt.white, total)))")

        // Param sets to compare. v0.3.4.0 default + 3 aggressive variants.
        let paramSets: [(label: String, params: LineArtEnhanceFilter.Parameters)] = [
            ("v0.3.4.0 default (60/200)",  .init(darkCutoff: 60,  lightCutoff: 200)),
            ("Aggressive (80/180)",        .init(darkCutoff: 80,  lightCutoff: 180)),
            ("Very aggressive (100/160)",  .init(darkCutoff: 100, lightCutoff: 160)),
            ("Threshold-like (110/145)",   .init(darkCutoff: 110, lightCutoff: 145)),
        ]

        for entry in paramSets {
            var buf = originalBuf
            LineArtEnhanceFilter.applyOnGrayscale(
                buffer: &buf, width: w, height: h,
                parameters: entry.params
            )
            let h2 = histogram(buf)
            let halo2 = haloZoneCount(h2)
            let ext2 = extremeCount(h2)
            print("\(entry.label.padding(toLength: 35, withPad: " ", startingAt: 0))| \(halo2) (\(pct(halo2, total)))  | \(ext2.black + ext2.white) (\(pct(ext2.black + ext2.white, total)))")
        }

        // Also try median-only (no levels) and levels-only (no median) for
        // ablation — which stage does the heavy lifting?
        print("")
        print("Ablation:")

        do {
            var buf = originalBuf
            LineArtEnhanceFilter.median3x3InPlace(buffer: &buf, width: w, height: h)
            let h2 = histogram(buf)
            print("Median 3×3 only (no levels)        | \(haloZoneCount(h2)) (\(pct(haloZoneCount(h2), total)))  | \(extremeCount(h2).black + extremeCount(h2).white) (\(pct(extremeCount(h2).black + extremeCount(h2).white, total)))")
        }

        do {
            var buf = originalBuf
            LineArtEnhanceFilter.applyLevelsInPlace(
                buffer: &buf, darkCutoff: 60, lightCutoff: 200
            )
            let h2 = histogram(buf)
            print("Levels only (60/200, no median)    | \(haloZoneCount(h2)) (\(pct(haloZoneCount(h2), total)))  | \(extremeCount(h2).black + extremeCount(h2).white) (\(pct(extremeCount(h2).black + extremeCount(h2).white, total)))")
        }

        print("")
        XCTAssertTrue(true)  // measurement-only
    }

    private func pct(_ value: Int, _ total: Int) -> String {
        return String(format: "%.2f%%", Double(value) / Double(total) * 100.0)
    }
}
