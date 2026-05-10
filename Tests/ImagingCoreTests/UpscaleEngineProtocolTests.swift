import XCTest
@testable import ImagingCore

final class UpscaleEngineProtocolTests: XCTestCase {
    func testUpscaleRequestRoundtrip() {
        let request = UpscaleRequest(
            inputURL: URL(fileURLWithPath: "/tmp/in.png"),
            outputURL: URL(fileURLWithPath: "/tmp/out.png"),
            modelName: "realesrgan-x4plus",
            scale: 4,
            tileSize: 256,
            outputFormat: .png
        )
        XCTAssertEqual(request.modelName, "realesrgan-x4plus")
        XCTAssertEqual(request.scale, 4)
        XCTAssertEqual(request.tileSize, 256)
        XCTAssertEqual(request.outputFormat, .png)
    }

    func testUpscaleRequestDefaults() {
        let request = UpscaleRequest(
            inputURL: URL(fileURLWithPath: "/tmp/in.png"),
            outputURL: URL(fileURLWithPath: "/tmp/out.png"),
            modelName: "realesrgan-x4plus",
            scale: 4
        )
        XCTAssertEqual(request.tileSize, 0, "tileSize default = 0 (auto)")
        XCTAssertEqual(request.outputFormat, .png, "outputFormat default = png")
    }

    func testUpscaleErrorEquatable() {
        XCTAssertEqual(
            UpscaleError.binaryNotFound(path: "/usr/bin/x"),
            UpscaleError.binaryNotFound(path: "/usr/bin/x")
        )
        XCTAssertNotEqual(
            UpscaleError.binaryNotFound(path: "/a"),
            UpscaleError.binaryNotFound(path: "/b")
        )
    }

    func testEngineHealthOptionalDevice() {
        let healthy = EngineHealth(isAvailable: true, version: "v0.2.0", detectedDevice: "Apple M4")
        let pending = EngineHealth(isAvailable: false, version: "phase-2-pending")
        XCTAssertEqual(healthy.detectedDevice, "Apple M4")
        XCTAssertNil(pending.detectedDevice)
    }
}
