import XCTest
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import CoreMLEngine
import ImagingCore

/// Heavier integration test for the multi-tile code path. Disabled by default
/// (set `RUN_MULTITILE=1` env var or use `swift test --filter MultiTile` to opt in)
/// because each invocation runs the model 4× (~2-3 s).
final class MultiTileTest: XCTestCase {

    func test_upscale_4tile_1024x1024_producesCorrectDimensions() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_MULTITILE"] == "1",
                          "Skip by default — set RUN_MULTITILE=1 to enable")

        // Reuse the /tmp/fixture-1024.png produced by the dev workflow,
        // or generate inline if missing.
        let fixtureURL = URL(fileURLWithPath: "/tmp/fixture-1024.png")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("/tmp/fixture-1024.png missing; generate via spike tools")
        }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let outputURL = tmpDir.appendingPathComponent("upscaled-4096.png")
        let request = UpscaleRequest(
            inputURL: fixtureURL,
            outputURL: outputURL,
            modelName: "realesrgan-x4plus",
            scale: 4
        )

        let engine = try CoreMLEngine()
        var maxTile = 0
        var totalTiles = 0
        var resultDims: (Int, Int)? = nil

        for try await event in engine.upscale(request: request) {
            switch event {
            case .tile(let current, let total):
                maxTile = max(maxTile, current)
                totalTiles = total
            case .completed(let result):
                let source = CGImageSourceCreateWithURL(result.outputURL as CFURL, nil)!
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
                resultDims = (props[kCGImagePropertyPixelWidth] as! Int,
                              props[kCGImagePropertyPixelHeight] as! Int)
            case .failed(let err):
                XCTFail("Engine failed: \(err)")
            case .started, .percentage:
                break
            }
        }

        XCTAssertEqual(totalTiles, 4, "1024×1024 ÷ 512 = 2×2 = 4 tiles")
        XCTAssertEqual(maxTile, 4, "expected all tiles completed")
        if let (w, h) = resultDims {
            XCTAssertEqual(w, 4096)
            XCTAssertEqual(h, 4096)
        } else {
            XCTFail("could not read output dimensions")
        }
    }
}
