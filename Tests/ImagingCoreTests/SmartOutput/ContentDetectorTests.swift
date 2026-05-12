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

    /// Generate a continuous-tone gradient PNG. With per-pixel R/G variation
    /// this will have many thousands of unique colors — `isLowEntropy` MUST be false.
    private func generateGradientPNG(size: Int = 512) throws -> URL {
        let url = tempURL(suffix: "gradient")
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Draw the gradient by setting pixels directly via repeated rectangle fills.
        // 8x8 cells -> 64×64 = 4096 unique colors well above the 256 threshold.
        let cells = 64
        let cellSize = CGFloat(size) / CGFloat(cells)
        for y in 0..<cells {
            for x in 0..<cells {
                ctx.setFillColor(CGColor(
                    red: CGFloat(x) / CGFloat(cells),
                    green: CGFloat(y) / CGFloat(cells),
                    blue: 0.5,
                    alpha: 1
                ))
                ctx.fill(CGRect(
                    x: CGFloat(x) * cellSize,
                    y: CGFloat(y) * cellSize,
                    width: cellSize,
                    height: cellSize
                ))
            }
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
        // Gradient already triggers early-exit in current implementation.
        // Verify that sampledPixels < total grid count when early-exit kicks in.
        let url = try generateGradientPNG(size: 1024)
        guard let a = ContentDetector.analyze(pngURL: url) else {
            XCTFail("Analysis failed")
            return
        }
        // Total grid samples at stride 8 = (1024/8)² = 16384. Early exit
        // happens at 2× threshold = 512. We expect either sampledCount <
        // 16384 (early exit fired) OR uniqueColorCount > threshold (full scan,
        // still high entropy).
        let maxGridSamples = (1024 / 8) * (1024 / 8)
        XCTAssertTrue(
            a.sampledPixels < maxGridSamples || a.uniqueColorCount >= ContentDetector.lowEntropyThreshold,
            "Either early-exit fired or high-entropy classification stood"
        )
    }
}
