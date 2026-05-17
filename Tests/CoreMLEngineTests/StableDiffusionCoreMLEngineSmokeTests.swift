import XCTest
import ImagingCore
@testable import CoreMLEngine

/// Smoke test that exercises the real SDXL inference pipeline end-to-end.
/// Skipped on CI (model not installed) — runs only on operator's M4 Pro
/// after first-launch download has populated the bundle.
///
/// Intentionally short (4 steps, smallest image count) to keep test
/// runtime ~30-60 seconds on M-series; not a quality benchmark.
final class StableDiffusionCoreMLEngineSmokeTests: XCTestCase {

    func test_probe_returnsNotAvailable_whenModelMissing() async throws {
        // Hermetic — does not require the real bundle.
        let engine = StableDiffusionCoreMLEngine()
        let health = try await engine.probe()
        // We can't assert .isAvailable absolutely (operator may have it installed),
        // but version + device fields must be coherent.
        if health.isAvailable {
            XCTAssertNotNil(health.detectedDevice)
            XCTAssertNotEqual(health.version, "model-not-installed")
        } else {
            XCTAssertEqual(health.version, "model-not-installed")
            XCTAssertNil(health.detectedDevice)
        }
    }

    func test_generate_returnsModelNotInstalled_whenAbsent() async throws {
        let installed = await MainActor.run { ModelDownloadManager.shared.isInstalled() }
        try XCTSkipIf(installed, "Skipped — real bundle present, this test asserts the absent path")

        let engine = StableDiffusionCoreMLEngine()
        let request = GenerationRequest(
            prompt: "coloring book test",
            seed: 42,
            steps: 4,
            cfgScale: 7.0,
            width: 1024, height: 1024
        )
        var sawNotInstalled = false
        do {
            for try await event in engine.generate(request: request) {
                if case .failed(let err) = event, err == .modelNotInstalled {
                    sawNotInstalled = true
                }
            }
        } catch GenerationError.modelNotInstalled {
            sawNotInstalled = true
        }
        XCTAssertTrue(sawNotInstalled, "Engine must surface .modelNotInstalled when bundle missing")
    }

    func test_smokeGenerate_real4StepOutput() async throws {
        let installed = await MainActor.run { ModelDownloadManager.shared.isInstalled() }
        try XCTSkipUnless(installed, "Skipped — SDXL bundle not installed (CI / first-launch-pending)")

        let engine = StableDiffusionCoreMLEngine()
        let request = GenerationRequest(
            prompt: "a simple coloring book page of a fox, black outline, white background",
            seed: 42,
            steps: 4,        // smoke: minimum credible count
            cfgScale: 7.0,
            width: 1024, height: 1024
        )

        var stepsSeen = 0
        var output: GenerationResult?
        var failure: GenerationError?

        for try await event in engine.generate(request: request) {
            switch event {
            case .started: break
            case .step: stepsSeen += 1
            case .completed(let r): output = r
            case .failed(let e): failure = e
            }
        }

        XCTAssertNil(failure, "Smoke gen must not fail with installed bundle")
        guard let result = output else {
            XCTFail("No completion event received"); return
        }
        XCTAssertGreaterThan(stepsSeen, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: result.outputURL.path)
        let size = (attrs[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 50_000, "Output PNG too small to be a real 1024² image")
        XCTAssertEqual(result.seed, 42)
        XCTAssertGreaterThan(result.durationMs, 0)
    }
}
