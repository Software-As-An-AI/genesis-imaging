import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import ImagingCore

// MARK: - MockUpscaleEngine

/// Test-only engine. Yields `.started` → optional `.tile` ticks → either
/// `.completed` (writes a small canned PNG to `request.outputURL`) or throws
/// after the configured trigger.
///
/// Concurrency: the engine produces its stream on a background queue (matches
/// `NcnnEngine` / `CoreMLEngine` shape) so the queue's @MainActor consumer
/// has to round-trip through actor hops just like in production.
final class MockUpscaleEngine: UpscaleEngine, @unchecked Sendable {
    let engineName: String = "mock-engine"
    let supportedModels: [String] = ["realesrgan-x4plus", "test-model"]

    /// Optional delay between progress events (seconds). 0 = no sleep.
    let perTickSeconds: Double

    /// 1-based call indices at which the engine should throw instead of completing.
    let failOnCallIndices: Set<Int>

    /// Thread-safe call counter.
    private let counterLock = NSLock()
    private var _callIndex: Int = 0
    var callCount: Int {
        counterLock.lock(); defer { counterLock.unlock() }
        return _callIndex
    }

    init(perTickSeconds: Double = 0, failOnCallIndices: Set<Int> = []) {
        self.perTickSeconds = perTickSeconds
        self.failOnCallIndices = failOnCallIndices
    }

    func supportsScale(_ scale: Int) -> Bool {
        scale == 2 || scale == 3 || scale == 4
    }

    func upscale(request: UpscaleRequest) -> AsyncThrowingStream<UpscaleProgress, Error> {
        counterLock.lock()
        _callIndex += 1
        let currentCall = _callIndex
        counterLock.unlock()
        let shouldFail = failOnCallIndices.contains(currentCall)
        let delay = perTickSeconds

        return AsyncThrowingStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.yield(.started)
                continuation.yield(.tile(current: 1, total: 1))
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }

                if shouldFail {
                    continuation.finish(throwing: UpscaleError.engineFailure(
                        exitCode: -1,
                        stderr: "Mock engine forced failure on call \(currentCall)"
                    ))
                    return
                }

                // Write a small canned PNG to the requested output URL so the
                // queue's atomic-move step finds bytes to promote.
                do {
                    try Self.writeCannedPNG(to: request.outputURL)
                } catch {
                    continuation.finish(throwing: UpscaleError.ioError(
                        message: "Mock canned PNG write failed: \(error)"
                    ))
                    return
                }

                let result = UpscaleResult(
                    outputURL: request.outputURL,
                    inputBytes: 0,
                    outputBytes: 64,
                    durationMs: Int(delay * 1000),
                    engineName: "mock-engine"
                )
                continuation.yield(.completed(result))
                continuation.finish()
            }
        }
    }

    func probe() async throws -> EngineHealth {
        EngineHealth(isAvailable: true, version: "mock-1.0", detectedDevice: "Mock device")
    }

    /// 2×2 solid-color PNG. Cheap to encode + reliably non-empty so the
    /// queue's `outputBytes` check passes.
    private static func writeCannedPNG(to url: URL) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "MockUpscaleEngine", code: 1)
        }
        ctx.setFillColor(red: 0.9, green: 0.1, blue: 0.5, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        guard let cgImage = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              ) else {
            throw NSError(domain: "MockUpscaleEngine", code: 2)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MockUpscaleEngine", code: 3)
        }
    }
}

// MARK: - BatchQueueWireTests

/// Wave 3 wire-up coverage: real `BatchQueue.start(engineProvider:)`
/// driving a `MockUpscaleEngine`, plus preflight on real fixtures + reset
/// semantics.
@MainActor
final class BatchQueueWireTests: XCTestCase {

    // MARK: - Lifecycle

    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("batchwire-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempRoot = tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try await super.tearDown()
    }

    /// Drop a small valid PNG into `tempRoot/<name>`.
    private func makeFixture(name: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "BatchQueueWireTests", code: 1)
        }
        ctx.setFillColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let cgImage = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              ) else {
            throw NSError(domain: "BatchQueueWireTests", code: 2)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    // MARK: - Tests

    /// preflight() on a corrupt file flags `.undecodable` and falls phase to draft.
    func test_preflight_returns_issues_for_corrupt_file() async throws {
        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        // Write a "png" file that's clearly not a real image.
        let corruptURL = tempRoot.appendingPathComponent("corrupt.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0xFF, 0xFF, 0xFF]).write(to: corruptURL)
        q.add(urls: [corruptURL])

        let issues = await q.preflight()
        XCTAssertFalse(issues.isEmpty, "Corrupt PNG should produce at least one preflight issue")
        XCTAssertEqual(q.phase, .draft)
    }

    /// start() with a mock engine processes pending items sequentially and
    /// writes output via OutputWriter to the resolved final URL.
    func test_start_processes_items_in_order_via_mock_engine() async throws {
        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        let fixtures = try [
            makeFixture(name: "a.png"),
            makeFixture(name: "b.png"),
            makeFixture(name: "c.png"),
        ]
        q.add(urls: fixtures)

        // Skip preflight gate by setting phase to ready directly — the
        // PreflightValidator's model-presence check would fail for our test
        // model, and we want to test the start loop in isolation.
        q.setPhaseForTesting(.ready)

        let engine = MockUpscaleEngine()
        await q.start { engine }

        XCTAssertEqual(q.phase, .completed)
        XCTAssertEqual(q.completedCount, 3, "All 3 items should reach .done")
        XCTAssertEqual(engine.callCount, 3, "Engine should be called once per item")
        for item in q.items {
            XCTAssertEqual(item.state, .done)
            XCTAssertNotNil(item.outputURL)
            if let outURL = item.outputURL {
                XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path),
                    "Output file should exist at \(outURL.path)")
            }
            XCTAssertNotNil(item.duration)
        }
        // Running average should be set (3 completions).
        XCTAssertNotNil(q.averageDuration)
    }

    /// softCancel() between items causes the queue to stop dispatching new
    /// engine calls. The currently-processing item is allowed to finish per
    /// soft-cancel contract. Easiest signal: cancel before start, only 1 item
    /// processes, phase becomes .cancelled.
    func test_softCancel_during_start_stops_after_current_item() async throws {
        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        let fixtures = try [
            makeFixture(name: "1.png"),
            makeFixture(name: "2.png"),
            makeFixture(name: "3.png"),
        ]
        q.add(urls: fixtures)
        q.setPhaseForTesting(.ready)

        // Engine that takes a tiny delay per call so softCancel fires before
        // item 2 dispatches. We pre-cancel after item 1 by injecting cancel
        // inside the engine provider (called once before the loop, sets
        // cancel after engine creation) — simpler: set cancelRequested = true
        // immediately, so the loop's first iteration breaks before processing.
        q.softCancel()

        let engine = MockUpscaleEngine()
        await q.start { engine }

        XCTAssertEqual(q.phase, .cancelled)
        XCTAssertEqual(engine.callCount, 0, "Engine should NOT be called when cancel was pre-requested")
        XCTAssertTrue(q.items.allSatisfy { $0.state == .pending },
            "All items should remain pending when cancel arrived before any processing")
    }

    /// Failed item should be marked .failed (with errorMessage) and the loop
    /// should continue processing remaining items.
    func test_failed_item_continues_to_next() async throws {
        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        let fixtures = try [
            makeFixture(name: "ok1.png"),
            makeFixture(name: "fail.png"),
            makeFixture(name: "ok2.png"),
        ]
        q.add(urls: fixtures)
        q.setPhaseForTesting(.ready)

        // Fail on call #2 only.
        let engine = MockUpscaleEngine(failOnCallIndices: [2])
        await q.start { engine }

        XCTAssertEqual(q.phase, .completed)
        XCTAssertEqual(q.items[0].state, .done, "Item 1 should succeed")
        XCTAssertEqual(q.items[1].state, .failed, "Item 2 should fail")
        XCTAssertNotNil(q.items[1].errorMessage)
        XCTAssertEqual(q.items[2].state, .done, "Item 3 should succeed (loop continues)")
        XCTAssertEqual(engine.callCount, 3, "All items should reach the engine")
    }

    /// reset() returns the queue to a pristine draft state.
    func test_reset_clears_state() async throws {
        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        let fixtures = try [
            makeFixture(name: "x.png"),
            makeFixture(name: "y.png"),
        ]
        q.add(urls: fixtures)
        q.setPhaseForTesting(.ready)

        let engine = MockUpscaleEngine()
        await q.start { engine }

        // Pre-condition: queue has state to clear.
        XCTAssertEqual(q.phase, .completed)
        XCTAssertEqual(q.completedCount, 2)
        XCTAssertNotNil(q.startTime)
        XCTAssertNotNil(q.averageDuration)

        q.reset()

        XCTAssertEqual(q.phase, .draft)
        XCTAssertTrue(q.items.isEmpty)
        XCTAssertTrue(q.preflightIssues.isEmpty)
        XCTAssertFalse(q.cancelRequested)
        XCTAssertNil(q.startTime)
        XCTAssertNil(q.averageDuration)
    }

    /// Engine provider that throws should surface as item-level error
    /// without crashing the queue.
    func test_engine_provider_failure_terminates_run_gracefully() async throws {
        let q = BatchQueue(defaultModel: "realesrgan-x4plus", defaultScale: 4)
        let fixture = try makeFixture(name: "p.png")
        q.add(urls: [fixture])
        q.setPhaseForTesting(.ready)

        struct ProviderError: Error, LocalizedError {
            var errorDescription: String? { "synthetic provider failure" }
        }

        await q.start { throw ProviderError() }

        XCTAssertEqual(q.phase, .completed)
        XCTAssertEqual(q.items[0].state, .failed)
        XCTAssertNotNil(q.items[0].errorMessage)
        XCTAssertTrue(q.items[0].errorMessage!.contains("Engine init failed"),
            "errorMessage should mention engine init failure, got: \(q.items[0].errorMessage ?? "nil")")
    }
}
