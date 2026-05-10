import XCTest
import ImagingCore
@testable import NcnnEngine

/// End-to-end test using the real ncnn binary. Skipped if the binary hasn't
/// been fetched (CI must run `./scripts/fetch-ncnn-binary.sh` before tests).
final class NcnnEngineIntegrationTests: XCTestCase {

    private var fixtureURL: URL {
        // Resource emitted by SwiftPM .process("Resources") for this test target.
        guard let url = Bundle.module.url(forResource: "tiny-32x32", withExtension: "png") else {
            fatalError("tiny-32x32.png not bundled — check Package.swift testTarget resources")
        }
        return url
    }

    private func skipIfBinaryUnavailable() throws {
        do {
            _ = try BinaryLocator.defaultBinaryURL()
            _ = try BinaryLocator.defaultModelsDirectory()
        } catch {
            throw XCTSkip("ncnn binary not installed — run ./scripts/fetch-ncnn-binary.sh: \(error)")
        }
    }

    func testEngineConstruction() throws {
        try skipIfBinaryUnavailable()
        let engine = try NcnnEngine()
        XCTAssertEqual(engine.engineName, "ncnn-vulkan")
        XCTAssertTrue(engine.supportedModels.contains("realesrgan-x4plus"))
        XCTAssertTrue(engine.supportsScale(4))
        XCTAssertFalse(engine.supportsScale(8))
    }

    func testEngineConstructionThrowsForMissingBinary() {
        let bogusBinary = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)")
        XCTAssertThrowsError(try NcnnEngine(binaryURL: bogusBinary)) { error in
            guard case .binaryNotFound = error as? UpscaleError else {
                return XCTFail("expected binaryNotFound, got \(error)")
            }
        }
    }

    func testProbeReportsAvailable() async throws {
        try skipIfBinaryUnavailable()
        let engine = try NcnnEngine()
        let health = try await engine.probe()
        XCTAssertTrue(health.isAvailable)
        XCTAssertEqual(health.version, "ncnn-vulkan-v0.2.0")
    }

    func testUpscaleSmallFixture() async throws {
        try skipIfBinaryUnavailable()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ncnn-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = try NcnnEngine()
        let request = UpscaleRequest(
            inputURL: fixtureURL,
            outputURL: outputURL,
            modelName: "realesrgan-x4plus",
            scale: 4,
            tileSize: 0,
            outputFormat: .png
        )

        var sawStarted = false
        var progressSamples: [Double] = []
        var result: UpscaleResult?

        for try await event in engine.upscale(request: request) {
            switch event {
            case .started:
                sawStarted = true
            case .percentage(let p):
                progressSamples.append(p)
            case .completed(let r):
                result = r
            case .tile, .failed:
                break
            }
        }

        XCTAssertTrue(sawStarted, "expected .started event")
        XCTAssertGreaterThanOrEqual(
            progressSamples.count, 1,
            "expected at least one progress sample, got: \(progressSamples)"
        )
        XCTAssertNotNil(result, "expected .completed event")

        // Verify output exists and was written.
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let outputSize = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(outputSize, 0, "output file should be non-empty")

        XCTAssertEqual(result?.engineName, "ncnn-vulkan-v0.2.0")
        XCTAssertGreaterThan(result?.outputBytes ?? 0, result?.inputBytes ?? Int.max,
                             "4× upscaled PNG should be larger than 32×32 source")
    }

    func testInvalidInputFileFailsGracefully() async throws {
        try skipIfBinaryUnavailable()

        // ncnn returns exit 0 for invalid input but writes "decode image ... failed"
        // to stderr. Our wrapper must detect this and surface an engineFailure.
        let bogusInput = URL(fileURLWithPath: "/tmp/genesis-imaging-no-such-input-\(UUID().uuidString).png")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ncnn-fail-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let engine = try NcnnEngine()
        let request = UpscaleRequest(
            inputURL: bogusInput,
            outputURL: outputURL,
            modelName: "realesrgan-x4plus",
            scale: 4
        )

        do {
            for try await _ in engine.upscale(request: request) {}
            XCTFail("expected engineFailure error")
        } catch let UpscaleError.engineFailure(_, stderr) {
            XCTAssertFalse(stderr.isEmpty, "stderr should contain failure detail")
            XCTAssertTrue(
                stderr.lowercased().contains("decode") || stderr.lowercased().contains("failed"),
                "stderr should mention decode failure, got: \(stderr)"
            )
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testStderrFailureDetectionHelper() {
        XCTAssertTrue(NcnnEngine.stderrIndicatesFailure(
            "decode image /tmp/x.png failed"
        ))
        XCTAssertTrue(NcnnEngine.stderrIndicatesFailure(
            "Some prefix\nencode image FAILED\n"
        ))
        XCTAssertFalse(NcnnEngine.stderrIndicatesFailure(
            "[0 Apple M4 Pro] queueC=0[1]\n0.00%\n"
        ))
        XCTAssertFalse(NcnnEngine.stderrIndicatesFailure(""))
    }

    func testBuildArgumentsLayout() {
        let request = UpscaleRequest(
            inputURL: URL(fileURLWithPath: "/tmp/in.png"),
            outputURL: URL(fileURLWithPath: "/tmp/out.png"),
            modelName: "realesrgan-x4plus",
            scale: 4,
            tileSize: 256
        )
        let modelsDir = URL(fileURLWithPath: "/opt/models")
        let args = NcnnEngine.buildArguments(request: request, modelsDirectory: modelsDir)
        XCTAssertEqual(args, [
            "-i", "/tmp/in.png",
            "-o", "/tmp/out.png",
            "-n", "realesrgan-x4plus",
            "-s", "4",
            "-t", "256",
            "-m", "/opt/models",
        ])
    }
}
