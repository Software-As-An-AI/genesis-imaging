import XCTest
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import CoreMLEngine
import ImagingCore

/// Faz 2 acceptance tests for the Core ML engine.
///
/// Requires the bundled model at `Resources/models/RealESRGAN_x4plus.mlmodel`
/// (fetched via `scripts/fetch-coreml-model.sh`). Tests skip with `XCTSkip`
/// when the model is missing so the test suite still runs on fresh clones
/// before `fetch-coreml-model.sh` is invoked.
final class CoreMLEngineTests: XCTestCase {

    /// True when the bundled Core ML model can be located.
    private func modelAvailable() -> Bool {
        (try? ModelLocator.defaultModelURL()) != nil
    }

    // MARK: - init / probe

    func test_init_succeeds_whenModelPresent() throws {
        try XCTSkipUnless(modelAvailable(), "Core ML model not bundled — run scripts/fetch-coreml-model.sh")
        let engine = try CoreMLEngine()
        XCTAssertEqual(engine.engineName, "coreml")
        XCTAssertTrue(engine.supportedModels.contains("realesrgan-x4plus"))
        XCTAssertTrue(engine.supportsScale(4))
        XCTAssertFalse(engine.supportsScale(2))
    }

    func test_init_throws_whenModelURLInvalid() {
        let bogusURL = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mlmodel")
        do {
            _ = try CoreMLEngine(modelURL: bogusURL)
            XCTFail("Expected init to throw for missing model")
        } catch let error as UpscaleError {
            switch error {
            case .modelNotFound, .ioError:
                break  // either is acceptable
            default:
                XCTFail("Expected modelNotFound or ioError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func test_probe_reportsAvailability() async throws {
        try XCTSkipUnless(modelAvailable(), "Core ML model not bundled")
        let engine = try CoreMLEngine()
        let health = try await engine.probe()
        XCTAssertTrue(health.isAvailable)
        XCTAssertTrue(health.version.contains("core-ml"))
        XCTAssertNotNil(health.detectedDevice)
    }

    // MARK: - End-to-end upscale (single tile, 512×512 → 2048×2048)

    func test_upscale_singleTile_512x512_producesOutput() async throws {
        try XCTSkipUnless(modelAvailable(), "Core ML model not bundled")
        guard let fixtureURL = Bundle.module.url(forResource: "fixture-512", withExtension: "png") else {
            throw XCTSkip("test fixture fixture-512.png missing from bundle")
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let outputURL = tmpDir.appendingPathComponent("upscaled.png")
        let request = UpscaleRequest(
            inputURL: fixtureURL,
            outputURL: outputURL,
            modelName: "realesrgan-x4plus",
            scale: 4
        )

        let engine = try CoreMLEngine()
        var sawStarted = false
        var sawCompleted = false
        var seenTileMax = 0
        var resultDims: (Int, Int)? = nil

        let stream = engine.upscale(request: request)
        for try await event in stream {
            switch event {
            case .started:
                sawStarted = true
            case .tile(let current, _):
                seenTileMax = max(seenTileMax, current)
            case .percentage:
                break
            case .completed(let result):
                sawCompleted = true
                XCTAssertEqual(result.engineName, "core-ml-realesrgan-mszpro")
                XCTAssertGreaterThan(result.outputBytes, 0)
                resultDims = readImageDimensions(at: result.outputURL)
            case .failed(let err):
                XCTFail("Engine failed: \(err)")
            }
        }

        XCTAssertTrue(sawStarted, "expected .started event")
        XCTAssertTrue(sawCompleted, "expected .completed event")
        XCTAssertEqual(seenTileMax, 1, "expected single tile completion (input is exactly 512×512)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), "output PNG missing")

        // Output must be 4× input dimensions
        if let (w, h) = resultDims {
            XCTAssertEqual(w, 2048)
            XCTAssertEqual(h, 2048)
        } else {
            XCTFail("could not read output dimensions")
        }
    }

    // MARK: - Helpers

    private func readImageDimensions(at url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
