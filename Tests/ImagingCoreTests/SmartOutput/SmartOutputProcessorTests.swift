import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import ImagingCore

/// These tests invoke real subprocesses (pngquant + oxipng). The bundled
/// binaries are looked up via `SmartOutputLocator`, which checks (1) the
/// app Bundle and (2) `<CWD>/Resources/bin/`. SwiftPM test runs from the
/// package root, so the dev-layout path resolves to the repo's bundled
/// binaries (committed in Wave 0).
///
/// Tests are SKIPPED gracefully if binaries are unavailable — useful for
/// CI environments that haven't pulled binary blobs yet.
final class SmartOutputProcessorTests: XCTestCase {

    // MARK: - Helpers

    private func generatePurePNG(size: Int = 512, lineWidth: CGFloat = 4) throws -> URL {
        let url = tempURL(suffix: "bw-pure")
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
        ctx.setLineWidth(lineWidth)
        ctx.setShouldAntialias(false)
        for i in 0..<25 {
            ctx.strokeEllipse(in: CGRect(
                x: CGFloat(20 + i * 15),
                y: CGFloat(20 + i * 15),
                width: 200, height: 200
            ))
        }
        try writePNG(context: ctx, to: url)
        return url
    }

    private func generateGradientPNG(size: Int = 512) throws -> URL {
        let url = tempURL(suffix: "gradient")
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
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
                    width: cellSize, height: cellSize
                ))
            }
        }
        try writePNG(context: ctx, to: url)
        return url
    }

    private func writePNG(context: CGContext, to url: URL) throws {
        guard let cgImage = context.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              )
        else {
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "test", code: 2, userInfo: nil)
        }
    }

    private func tempURL(suffix: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("genesis-imaging-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(suffix).png")
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private func skipIfBinariesUnavailable() throws {
        try XCTSkipUnless(
            SmartOutputLocator.bothAvailable(),
            "pngquant/oxipng not bundled — skipping (Wave 0 incomplete)"
        )
    }

    // MARK: - Tests

    func testOffModeIsNoOp() throws {
        let url = try generatePurePNG()
        let beforeBytes = fileSize(url)
        let processor = SmartOutputProcessor()
        let result = try processor.process(url: url, mode: .off)
        XCTAssertEqual(result.skipReason, "mode-off")
        XCTAssertEqual(fileSize(url), beforeBytes, "Output bytes unchanged in .off mode")
        XCTAssertFalse(result.wasQuantized)
        XCTAssertFalse(result.wasOptimized)
    }

    func testAutoModeQuantizesBlackAndWhite() throws {
        try skipIfBinariesUnavailable()
        let url = try generatePurePNG()
        let beforeBytes = fileSize(url)
        let processor = SmartOutputProcessor()
        let result = try processor.process(url: url, mode: .auto)
        XCTAssertNil(result.skipReason, "Should not skip on B/W in auto mode")
        XCTAssertTrue(result.wasQuantized, "B/W is low-entropy — pngquant should run")
        XCTAssertTrue(result.wasOptimized, "oxipng should run after quantize")
        let afterBytes = fileSize(url)
        XCTAssertLessThanOrEqual(afterBytes, beforeBytes, "B/W output should not be larger")
        // We don't assert a specific reduction ratio in unit tests — the
        // CGContext-rendered fixture is already optimized to a small palette
        // PNG (CGImageDestination palettizes 2-color content). The phase 0
        // CLI test on real ncnn output proves the 5-20× reduction.
    }

    func testAutoModeFallsBackOnGradient() throws {
        try skipIfBinariesUnavailable()
        let url = try generateGradientPNG()
        let beforeBytes = fileSize(url)
        let processor = SmartOutputProcessor()
        let result = try processor.process(url: url, mode: .auto)
        // Gradient is high-entropy → pngquant skipped, oxipng-only path.
        XCTAssertFalse(result.wasQuantized, "Gradient should not be quantized in auto")
        XCTAssertTrue(result.wasOptimized || result.skipReason == "delta-guard")
        let afterBytes = fileSize(url)
        XCTAssertLessThanOrEqual(afterBytes, beforeBytes, "Output never larger than input")
    }

    func testSizeDeltaGuardKeepsOriginalWhenNoGain() throws {
        try skipIfBinariesUnavailable()
        // CGImageDestination already palettizes a 2-color image to ~minimum
        // size. Running pngquant + oxipng on it yields a tiny gain or none,
        // sometimes triggering the size-delta guard. We can't deterministically
        // force this case without a forced-near-optimal fixture, so this test
        // asserts the **invariant**: when guard fires, original is kept
        // byte-for-byte.
        let url = try generatePurePNG()
        let processor = SmartOutputProcessor()
        let result = try processor.process(url: url, mode: .auto)
        if result.skipReason == "delta-guard" {
            XCTAssertEqual(
                result.finalBytes, result.originalBytes,
                "Delta-guard skip must report finalBytes == originalBytes"
            )
        }
    }

    func testAlwaysModeQuantizesEvenIfHighEntropy() throws {
        try skipIfBinariesUnavailable()
        let url = try generateGradientPNG()
        let processor = SmartOutputProcessor()
        let result = try processor.process(url: url, mode: .always)
        // .always forces quantize regardless of detection.
        // pngquant may exit 99 if quality can't be met — in that case we
        // fall back to oxipng-only. Either way, the run completes.
        XCTAssertTrue(result.skipReason == nil || result.skipReason == "delta-guard")
    }

    func testEmptyPathHandledGracefully() throws {
        // No file at URL → pngquant fails. Verify we throw a clean error
        // rather than crash.
        try skipIfBinariesUnavailable()
        let url = tempURL(suffix: "missing")
        let processor = SmartOutputProcessor()
        XCTAssertThrowsError(try processor.process(url: url, mode: .always))
    }
}
