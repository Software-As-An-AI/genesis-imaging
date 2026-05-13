import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import ImagingCore

/// Validates `ContentClassifier.fingerprint` produces expected metrics + that
/// `pickAdaptiveMode` routes content to the correct mode.
final class ContentFingerprintTests: XCTestCase {

    // MARK: - Fixture builders

    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("genesis-fingerprint-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(name).png")
    }

    /// Pure 2-color B/W image: white background + thin black lines, no
    /// anti-aliasing. nearBinaryScore ≈ 1.0, saturationScore ≈ 0.
    private func makePureBlackAndWhite(size: Int = 512) throws -> URL {
        let url = tempURL("pure-bw")
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.setLineWidth(4)
        ctx.setShouldAntialias(false)
        for i in 0..<15 {
            ctx.strokeEllipse(in: CGRect(
                x: CGFloat(20 + i * 16), y: CGFloat(20 + i * 16),
                width: 100, height: 100
            ))
        }
        try writePNG(ctx, to: url)
        return url
    }

    /// Anti-aliased line art: white + black with smoothing. nearBinary high
    /// (~0.85+), edgeDensity high.
    private func makeAntiAliasedLineArt(size: Int = 512) throws -> URL {
        let url = tempURL("aa-lineart")
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.setLineWidth(3)
        ctx.setShouldAntialias(true)  // <-- key difference
        for i in 0..<40 {
            let r = CGFloat(15 + i * 5)
            ctx.strokeEllipse(in: CGRect(
                x: CGFloat(size / 2) - r, y: CGFloat(size / 2) - r,
                width: 2 * r, height: 2 * r
            ))
        }
        try writePNG(ctx, to: url)
        return url
    }

    /// Photo-like fixture with random RGB per pixel — saturation high,
    /// nearBinary low.
    private func makePhotoLike(size: Int = 512) throws -> URL {
        let url = tempURL("photo")
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: size * bytesPerRow)
        var state: UInt32 = 0xDEADBEEF
        for i in 0..<(size * size) {
            state &*= 1664525
            state &+= 1013904223
            let off = i * bytesPerPixel
            buffer[off]     = UInt8(state & 0xFF)
            buffer[off + 1] = UInt8((state >> 8) & 0xFF)
            buffer[off + 2] = UInt8((state >> 16) & 0xFF)
            buffer[off + 3] = 0xFF
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = buffer.withUnsafeMutableBytes { ptr -> CGContext? in
            guard let base = ptr.baseAddress else { return nil }
            return CGContext(
                data: base, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }
        guard let ctx else {
            throw NSError(domain: "test", code: 1)
        }
        try writePNG(ctx, to: url)
        return url
    }

    private func writePNG(_ ctx: CGContext, to url: URL) throws {
        guard let cg = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              )
        else { throw NSError(domain: "test", code: 2) }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "test", code: 3)
        }
    }

    // MARK: - Tests

    func testPureBlackAndWhiteHasNearBinaryOne() throws {
        let url = try makePureBlackAndWhite()
        let fp = try XCTUnwrap(ContentClassifier.fingerprint(pngURL: url))
        XCTAssertGreaterThan(fp.nearBinaryScore, 0.95,
                             "Pure B/W should have near-binary > 0.95 (got \(fp.nearBinaryScore))")
        XCTAssertLessThan(fp.saturationScore, 0.02,
                          "Pure B/W should have saturation < 0.02")
    }

    func testPhotoHasLowNearBinaryAndHighSaturation() throws {
        let url = try makePhotoLike()
        let fp = try XCTUnwrap(ContentClassifier.fingerprint(pngURL: url))
        XCTAssertLessThan(fp.nearBinaryScore, 0.5,
                          "Photo should have near-binary < 0.5")
        XCTAssertGreaterThan(fp.saturationScore, 0.1,
                             "Photo should have saturation > 0.1")
    }

    func testAdaptivePickerRoutesPureBWToBinarize() throws {
        let url = try makePureBlackAndWhite()
        let fp = try XCTUnwrap(ContentClassifier.fingerprint(pngURL: url))
        let picked = ContentClassifier.pickAdaptiveMode(fingerprint: fp)
        // Pure 2-color B/W with no anti-aliasing → either binarize (low edge)
        // or colors8/lineart (higher edge). Both are valid for this fixture.
        XCTAssertTrue(
            picked == .binarize || picked == .colors8,
            "Pure B/W should route to binarize or lineart (got \(picked))"
        )
    }

    func testAdaptivePickerRoutesPhotoToNonBWMode() throws {
        // Photo fixture (random RGB) should route AWAY from B/W modes
        // (binarize / colors8 / colors32). At 512×512 stride-8 sampling
        // unique color count is bounded by 4096 samples so picker may
        // settle on softLoss; at 2048×2048+ it would reach .auto. Both are
        // acceptable for photo content — assert NOT routed to B/W modes.
        let url = try makePhotoLike()
        let fp = try XCTUnwrap(ContentClassifier.fingerprint(pngURL: url))
        let picked = ContentClassifier.pickAdaptiveMode(fingerprint: fp)
        XCTAssertFalse(
            picked == .binarize || picked == .colors8 || picked == .colors32,
            "Photo content must not route to B/W or limited-palette modes (got \(picked))"
        )
    }

    func testFingerprintHandlesMissingFile() {
        let bogus = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).png")
        XCTAssertNil(ContentClassifier.fingerprint(pngURL: bogus))
    }
}
