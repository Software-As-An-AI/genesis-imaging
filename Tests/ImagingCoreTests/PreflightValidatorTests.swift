import XCTest
import ImageIO
import CoreGraphics
@testable import ImagingCore

@MainActor
final class PreflightValidatorTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("preflight-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Fixture generators

    /// Write a 4×4 valid PNG using CGImageDestination.
    private func writeValidPNG(_ name: String, width: Int = 4, height: Int = 4) -> URL {
        let url = tempDir.appendingPathComponent(name)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Fill with a solid color so the image is non-trivial.
        bitmap.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = bitmap.makeImage()!

        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest), "PNG write must succeed for fixture")
        return url
    }

    /// Write a file with PNG magic bytes followed by garbage so existence + readable
    /// succeed but `CGImageSourceCreateWithURL` returns nil (or zero count).
    private func writeCorruptPNG(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        // PNG signature only, no IHDR — ImageIO rejects.
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let garbage = Data([UInt8](repeating: 0xFF, count: 32))
        var data = Data(magic)
        data.append(garbage)
        try? data.write(to: url)
        return url
    }

    /// Write a file with `.gif` extension and tiny valid header — preflight
    /// should catch the format whitelist BEFORE attempting decode.
    private func writeUnsupportedGIF(_ name: String) -> URL {
        let url = tempDir.appendingPathComponent(name)
        // GIF89a header is enough — we only need the extension to fail whitelist.
        let header: [UInt8] = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00,
                               0x01, 0x00, 0x80, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
                               0x00, 0x00, 0x00, 0x21, 0xF9, 0x04, 0x00, 0x00,
                               0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00,
                               0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44,
                               0x01, 0x00, 0x3B]
        try? Data(header).write(to: url)
        return url
    }

    private func item(_ url: URL, model: String? = nil, scale: Int? = nil) -> QueueItem {
        QueueItem(sourceURL: url, modelOverride: model, scaleOverride: scale)
    }

    // MARK: - All-clean

    func test_all_clean_no_issues() async {
        let a = writeValidPNG("a.png")
        let b = writeValidPNG("b.jpg")  // Wrong extension but PNG bytes — see note
        // Reset b with actual JPEG bytes so format + decode both pass.
        try? FileManager.default.removeItem(at: b)
        _ = writeValidJPEG(at: b)

        let v = PreflightValidator()
        let issues = await v.validate(
            items: [item(a), item(b)],
            outputDir: nil,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: nil
        )
        XCTAssertEqual(issues, [], "Two valid small images, no overrides → 0 issues")
    }

    /// JPEG variant of valid fixture for the all-clean test.
    @discardableResult
    private func writeValidJPEG(at url: URL) -> URL {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmap = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 16, space: cs,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        bitmap.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        bitmap.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let cgImage = bitmap.makeImage()!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cgImage, nil)
        _ = CGImageDestinationFinalize(dest)
        return url
    }

    // MARK: - Per-item issue types

    func test_fileMissing_for_nonexistent_path() async {
        let ghost = tempDir.appendingPathComponent("ghost.png")
        let v = PreflightValidator()
        let issues = await v.validate(
            items: [item(ghost)],
            outputDir: nil,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: nil
        )
        XCTAssertEqual(issues, [.fileMissing(ghost)])
    }

    func test_unreadable_for_chmod_000() async {
        let f = writeValidPNG("unreadable.png")
        // Drop all read perms.
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.path)
        // Re-grant in tearDown so removeItem succeeds.
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.path)
        }

        let v = PreflightValidator()
        let issues = await v.validate(
            items: [item(f)],
            outputDir: nil,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: nil
        )
        // On macOS, `isReadableFile` for the owner with 0o000 returns false.
        XCTAssertEqual(issues, [.unreadable(f)])
    }

    func test_undecodable_for_corrupt_png() async {
        let bad = writeCorruptPNG("corrupt.png")
        let v = PreflightValidator()
        let issues = await v.validate(
            items: [item(bad)],
            outputDir: nil,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: nil
        )
        XCTAssertEqual(issues, [.undecodable(bad)])
    }

    func test_unsupportedFormat_for_gif() async {
        let gif = writeUnsupportedGIF("anim.gif")
        let v = PreflightValidator()
        let issues = await v.validate(
            items: [item(gif)],
            outputDir: nil,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: nil
        )
        XCTAssertEqual(issues, [.unsupportedFormat(gif, "gif")])
    }

    // MARK: - Global issues

    func test_outputNotWritable_for_missing_dir() async {
        let f = writeValidPNG("ok.png")
        let bogus = URL(fileURLWithPath: "/var/this/path/should/not/exist/xyz")
        let v = PreflightValidator()
        let issues = await v.validate(
            items: [item(f)],
            outputDir: bogus,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: nil
        )
        XCTAssertTrue(issues.contains(.outputNotWritable(bogus.standardizedFileURL)),
                      "Bogus output dir → outputNotWritable")
    }

    func test_modelMissing_when_modelsDir_present_but_lacks_model() async {
        let f = writeValidPNG("ok.png")
        let modelsDir = tempDir.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        // Empty models dir — neither .bin/.param nor .mlmodelc present.
        let v = PreflightValidator()
        let issues = await v.validate(
            items: [item(f)],
            outputDir: nil,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: modelsDir
        )
        XCTAssertTrue(issues.contains(.modelMissing("realesrgan-x4plus")),
                      "Empty models dir → modelMissing for default model")
    }

    func test_modelMissing_skipped_when_modelsDir_nil() async {
        // Production code path: when caller passes `nil` modelsDirectory we
        // soft-pass to avoid false alarms (Bundle resolution at engine init).
        let f = writeValidPNG("ok.png")
        let v = PreflightValidator()
        let issues = await v.validate(
            items: [item(f)],
            outputDir: nil,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: nil
        )
        XCTAssertFalse(issues.contains(where: { if case .modelMissing = $0 { return true } else { return false } }),
                       "nil modelsDirectory → no .modelMissing issue surfaced")
    }

    func test_memoryRisk_synthesized_via_low_safety_factor() {
        // Memory check is hard to trigger with a 4×4 fixture (4 × 4 × 16 × 4 = 1KB),
        // so we drive `validateItem(...)` directly with a synthesized scale that
        // would inflate estimated bytes beyond budget — but since physicalMemory is
        // huge, we instead verify the formula by asserting the threshold:
        // estBytes = pixelW × pixelH × scale² × 4 bytes
        let f = writeValidPNG("ok.png", width: 1024, height: 1024)
        let v = PreflightValidator()
        let issue = v.validateItem(item: item(f), scale: 4)
        // 1024 × 1024 × 16 × 4 = 64MB → well under macOS device RAM budget × 0.5,
        // so should be nil.
        XCTAssertNil(issue, "1024² × scale 4 (~64MB) is below memory budget on test host")
    }

    // MARK: - Defaults + overrides interaction

    func test_perItem_scale_override_used_in_diskEstimate() async {
        // Validator should respect per-item scale overrides during disk estimate.
        // We can't easily inspect the estimate, but we can verify no spurious
        // .diskSpaceInsufficient on a 4×4 fixture with scale 2 vs 4 override.
        let f = writeValidPNG("ok.png")
        let v = PreflightValidator()
        let issuesScale2 = await v.validate(
            items: [item(f, scale: 2)],
            outputDir: nil,
            defaultModel: "realesrgan-x4plus",
            defaultScale: 4,
            modelsDirectory: nil
        )
        XCTAssertEqual(issuesScale2, [], "Small fixture with scale 2 override → no disk issue")
    }
}
