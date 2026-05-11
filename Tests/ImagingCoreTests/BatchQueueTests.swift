import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import ImagingCore

@MainActor
final class BatchQueueTests: XCTestCase {

    // MARK: - Helpers

    private func makeQueue(
        model: String = "realesrgan-x4plus",
        scale: Int = 4
    ) -> BatchQueue {
        BatchQueue(defaultModel: model, defaultScale: scale)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/genesis-imaging-batchtest/\(name)")
    }

    /// Write a small valid PNG to a unique temp location. Caller is
    /// responsible for cleanup. Shared with Wave 3 tests below.
    static func writeValidPNG(name: String, width: Int = 4, height: Int = 4) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("batchqueue-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "BatchQueueTests", code: 1)
        }
        ctx.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1.0)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
              ) else {
            throw NSError(domain: "BatchQueueTests", code: 2)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "BatchQueueTests", code: 3)
        }
        return url
    }

    // MARK: - add / remove

    func test_add_items_appends_in_order() {
        let q = makeQueue()
        q.add(urls: [url("a.png"), url("b.png"), url("c.png")])
        XCTAssertEqual(q.items.count, 3)
        XCTAssertEqual(q.items.map { $0.sourceURL.lastPathComponent },
                       ["a.png", "b.png", "c.png"])
        XCTAssertTrue(q.items.allSatisfy { $0.state == .pending })
    }

    func test_add_dedupes_same_URL() {
        let q = makeQueue()
        q.add(urls: [url("a.png"), url("a.png")])
        XCTAssertEqual(q.items.count, 1, "Same URL dropped twice → one item, not two")

        // Subsequent add with same URL also dedupes.
        q.add(urls: [url("a.png"), url("b.png")])
        XCTAssertEqual(q.items.count, 2)
        XCTAssertEqual(q.items.map { $0.sourceURL.lastPathComponent }, ["a.png", "b.png"])
    }

    func test_remove_by_id() {
        let q = makeQueue()
        q.add(urls: [url("a.png"), url("b.png"), url("c.png")])
        let middleID = q.items[1].id
        q.remove(itemID: middleID)
        XCTAssertEqual(q.items.count, 2)
        XCTAssertEqual(q.items.map { $0.sourceURL.lastPathComponent }, ["a.png", "c.png"])

        // No-op for unknown id.
        q.remove(itemID: UUID())
        XCTAssertEqual(q.items.count, 2)
    }

    // MARK: - setOverride

    func test_setOverride_updates_item() {
        let q = makeQueue()
        q.add(urls: [url("a.png")])
        let id = q.items[0].id

        q.setOverride(itemID: id, model: "realesr-animevideov3", scale: 2)
        XCTAssertEqual(q.items[0].modelOverride, "realesr-animevideov3")
        XCTAssertEqual(q.items[0].scaleOverride, 2)
        XCTAssertEqual(q.items[0].effectiveModel(batchDefault: "realesrgan-x4plus"),
                       "realesr-animevideov3")
        XCTAssertEqual(q.items[0].effectiveScale(batchDefault: 4), 2)

        // Clearing override falls back to batch default.
        q.setOverride(itemID: id, model: nil, scale: nil)
        XCTAssertNil(q.items[0].modelOverride)
        XCTAssertNil(q.items[0].scaleOverride)
        XCTAssertEqual(q.items[0].effectiveModel(batchDefault: "realesrgan-x4plus"),
                       "realesrgan-x4plus")
        XCTAssertEqual(q.items[0].effectiveScale(batchDefault: 4), 4)
    }

    // MARK: - ETA

    func test_eta_nil_before_first_completion() {
        let q = makeQueue()
        q.add(urls: [url("a.png"), url("b.png"), url("c.png")])
        XCTAssertNil(q.etaSeconds, "ETA undefined until first item completion")
        XCTAssertNil(q.averageDuration)
    }

    func test_eta_extrapolates_from_runningAverage() {
        let q = makeQueue()
        q.add(urls: [url("a.png"), url("b.png"), url("c.png"), url("d.png")])

        // Mark first as done + record 10s.
        q.items[0].state = .done
        q.recordCompletion(duration: 10)
        XCTAssertEqual(q.averageDuration ?? -1, 10, accuracy: 0.001)
        // 3 pending × 10s = 30s.
        XCTAssertEqual(q.etaSeconds ?? -1, 30, accuracy: 0.001)

        // Mark second done + record 20s. Running avg = (10 + 20) / 2 = 15.
        q.items[1].state = .done
        q.recordCompletion(duration: 20)
        XCTAssertEqual(q.averageDuration ?? -1, 15, accuracy: 0.001)
        // 2 pending × 15s = 30s.
        XCTAssertEqual(q.etaSeconds ?? -1, 30, accuracy: 0.001)
    }

    // MARK: - Cancel

    func test_softCancel_sets_flag() {
        let q = makeQueue()
        q.add(urls: [url("a.png")])
        XCTAssertFalse(q.cancelRequested)
        q.softCancel()
        XCTAssertTrue(q.cancelRequested)
    }

    // MARK: - Phase

    func test_phase_transition_draft_to_processing() async throws {
        let q = makeQueue()
        // Real fixture — preflight is now wired to `PreflightValidator`, so
        // a non-existent path would surface `.fileMissing` and block ready.
        let fixture = try BatchQueueTests.writeValidPNG(name: "phase-ok.png")
        defer { try? FileManager.default.removeItem(at: fixture) }
        q.add(urls: [fixture])
        XCTAssertEqual(q.phase, .draft)

        let issues = await q.preflight()
        XCTAssertEqual(issues.count, 0)
        XCTAssertEqual(q.phase, .ready)

        // Wave 1 compatibility: parameterless start() flips phase without
        // running the engine loop.
        await q.start()
        XCTAssertEqual(q.phase, .processing)
        XCTAssertNotNil(q.startTime)
    }

    func test_phase_falls_back_to_draft_when_preflight_has_issues() async {
        let q = makeQueue()
        // Path that does not exist on disk → `PreflightValidator` surfaces
        // `.fileMissing`. No injection needed.
        q.add(urls: [url("nonexistent.png")])

        let issues = await q.preflight()
        XCTAssertGreaterThanOrEqual(issues.count, 1,
            "Missing file should produce at least one issue")
        XCTAssertEqual(q.phase, .draft, "Issues block → user must fix before start")
    }

    // MARK: - completedCount semantics

    func test_completedCount_only_counts_done() {
        let q = makeQueue()
        q.add(urls: [url("a.png"), url("b.png"), url("c.png"), url("d.png"), url("e.png")])
        q.items[0].state = .done
        q.items[1].state = .done
        q.items[2].state = .failed
        q.items[3].state = .skipped
        // items[4] stays pending.

        XCTAssertEqual(q.completedCount, 2, "Only .done counts; failed/skipped/pending excluded")
        XCTAssertEqual(q.totalCount, 5)
    }

    // MARK: - QueueItem value semantics

    func test_queueItem_equatable_by_id_and_fields() {
        let id = UUID()
        let a = QueueItem(id: id, sourceURL: url("a.png"))
        var b = QueueItem(id: id, sourceURL: url("a.png"))
        XCTAssertEqual(a, b)

        b.state = .processing
        XCTAssertNotEqual(a, b, "Equality is structural, not identity-only")
    }
}
