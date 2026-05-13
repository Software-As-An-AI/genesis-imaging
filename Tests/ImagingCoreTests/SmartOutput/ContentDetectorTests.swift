import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import ImagingCore

final class ContentDetectorTests: XCTestCase {

    // MARK: - Helpers

    /// Generate a B/W coloring-book style PNG (pure black lines on white).
    /// With perfect black/white this is a 2-color image — `isLowEntropy` MUST be true.
    private func generateBlackAndWhitePNG(size: Int = 512) throws -> URL {
        let url = tempURL(suffix: "bw")
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.setLineWidth(4)
        ctx.setShouldAntialias(false)  // Pure 2-color image.
        for _ in 0..<10 {
            let cx = CGFloat.random(in: 50...(CGFloat(size) - 50))
            let cy = CGFloat.random(in: 50...(CGFloat(size) - 50))
            let r = CGFloat.random(in: 20...80)
            ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        try writePNG(context: ctx, to: url)
        return url
    }

    /// Generate a photo-like fixture by writing pseudo-random RGB per pixel.
    /// At 1024×1024 this produces ~500K-1M unique RGB values — far above the
    /// 65536 low-entropy threshold (raised 2026-05-13 iter 2 to admit ncnn-
    /// upscaled anti-aliased B/W content, which empirically measures 10K-15K
    /// unique colors). Keeps the high-entropy classification test meaningful.
    private func generateGradientPNG(size: Int = 2560) throws -> URL {
        let url = tempURL(suffix: "highentropy")
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: size * bytesPerRow)
        var state: UInt32 = 0xDEADBEEF
        for i in 0..<(size * size) {
            state &*= 1664525
            state &+= 1013904223  // LCG (Numerical Recipes)
            let off = i * bytesPerPixel
            buffer[off]     = UInt8(state & 0xFF)
            buffer[off + 1] = UInt8((state >> 8) & 0xFF)
            buffer[off + 2] = UInt8((state >> 16) & 0xFF)
            buffer[off + 3] = 0xFF  // alpha
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = buffer.withUnsafeMutableBytes { ptr -> CGContext? in
            guard let base = ptr.baseAddress else { return nil }
            return CGContext(
                data: base, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        guard let ctx else {
            throw NSError(domain: "test", code: 10, userInfo: nil)
        }
        try writePNG(context: ctx, to: url)
        return url
    }

    private func writePNG(context: CGContext, to url: URL) throws {
        guard let cgImage = context.makeImage() else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "makeImage failed"])
        }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "CGImageDestination create failed"])
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "PNG finalize failed"])
        }
    }

    private func tempURL(suffix: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("genesis-imaging-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(suffix).png")
    }

    // MARK: - Tests

    func testBlackAndWhiteDetectedAsLowEntropy() throws {
        let url = try generateBlackAndWhitePNG()
        let analysis = ContentDetector.analyze(pngURL: url)
        XCTAssertNotNil(analysis)
        guard let a = analysis else { return }
        XCTAssertTrue(a.isLowEntropy, "B/W image should be low-entropy (got \(a.uniqueColorCount) colors)")
        XCTAssertLessThan(a.uniqueColorCount, ContentDetector.lowEntropyThreshold)
    }

    func testGradientDetectedAsHighEntropy() throws {
        let url = try generateGradientPNG()
        let analysis = ContentDetector.analyze(pngURL: url)
        XCTAssertNotNil(analysis)
        guard let a = analysis else { return }
        XCTAssertFalse(a.isLowEntropy, "Gradient image should be high-entropy (got \(a.uniqueColorCount) colors)")
        XCTAssertGreaterThanOrEqual(a.uniqueColorCount, ContentDetector.lowEntropyThreshold)
    }

    func testMissingFileReturnsNil() {
        let bogusURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).png")
        let analysis = ContentDetector.analyze(pngURL: bogusURL)
        XCTAssertNil(analysis)
    }

    func testEarlyExitCeilingPreventsBlowup() throws {
        // Photo-like high-entropy fixture should trip either:
        //   (a) sampledPixels < total grid count → early-exit fired, or
        //   (b) uniqueColorCount ≥ threshold → full-scan high-entropy verdict
        let size = 2560
        let url = try generateGradientPNG(size: size)
        guard let a = ContentDetector.analyze(pngURL: url) else {
            XCTFail("Analysis failed")
            return
        }
        let maxGridSamples = (size / 8) * (size / 8)
        XCTAssertTrue(
            a.sampledPixels < maxGridSamples || a.uniqueColorCount >= ContentDetector.lowEntropyThreshold,
            "Either early-exit fired or high-entropy classification stood"
        )
    }
}
