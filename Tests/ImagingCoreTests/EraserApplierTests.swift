import XCTest
@testable import ImagingCore

final class EraserApplierTests: XCTestCase {

    // MARK: - Circle rasterization

    func testApplySingleStroke_fillsCircleArea() {
        let w = 32, h = 32
        var buf = [UInt8](repeating: 0, count: w * h)  // all black
        let stroke = BrushStroke(
            points: [CGPoint(x: 16, y: 16)],
            radius: 5
        )
        EraserApplier.apply(stroke: stroke, to: &buf, width: w, height: h)

        // Center pixel must be white (filled).
        XCTAssertEqual(buf[16 * w + 16], 255)
        // Pixel 6 px away horizontally — outside the radius-5 circle → still black.
        XCTAssertEqual(buf[16 * w + 23], 0)
        // Diagonal corner — far outside → still black.
        XCTAssertEqual(buf[0], 0)
    }

    func testApply_doesNotOverflowBuffer() {
        // Stroke at the very edge of the image — must not crash even if
        // the bounding box of the circle clips off-canvas.
        let w = 16, h = 16
        var buf = [UInt8](repeating: 0, count: w * h)
        let stroke = BrushStroke(points: [CGPoint(x: 0, y: 0)], radius: 8)
        EraserApplier.apply(stroke: stroke, to: &buf, width: w, height: h)
        // Top-left pixel should be filled.
        XCTAssertEqual(buf[0], 255)
        // Bottom-right corner should NOT be filled (outside radius).
        XCTAssertEqual(buf[(h - 1) * w + (w - 1)], 0)
    }

    func testCompose_appliesAllStrokesInOrder() {
        let w = 16, h = 16
        var buf = [UInt8](repeating: 0, count: w * h)
        let strokes = [
            BrushStroke(points: [CGPoint(x: 4, y: 4)], radius: 2),
            BrushStroke(points: [CGPoint(x: 12, y: 12)], radius: 2),
        ]
        EraserApplier.compose(strokes: strokes, onto: &buf, width: w, height: h)
        XCTAssertEqual(buf[4 * w + 4], 255)
        XCTAssertEqual(buf[12 * w + 12], 255)
        XCTAssertEqual(buf[8 * w + 8], 0)  // gap between the two strokes
    }

    // MARK: - Densification

    func testDensify_keepsClosePointsUnchanged() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0)]
        let dense = EraserApplier.densify(pts, step: 5)
        XCTAssertEqual(dense.count, 2)
        XCTAssertEqual(dense, pts)
    }

    func testDensify_interpolatesFarPoints() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let dense = EraserApplier.densify(pts, step: 10)
        // 100 / 10 = 10 segments → 10 added points + initial = 11 total
        XCTAssertEqual(dense.count, 11)
        // First and last must remain unchanged.
        XCTAssertEqual(dense.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(dense.last, CGPoint(x: 100, y: 0))
        // 5th point should be at x ≈ 50.
        XCTAssertEqual(dense[5].x, 50, accuracy: 0.01)
    }

    func testDensify_handlesEmptyAndSingle() {
        XCTAssertEqual(EraserApplier.densify([], step: 5), [])
        let single = [CGPoint(x: 1, y: 1)]
        XCTAssertEqual(EraserApplier.densify(single, step: 5), single)
    }

    // MARK: - OutputWriter.resolveEditedURL

    func testResolveEditedURL_appendsEditedSuffix() {
        let src = URL(fileURLWithPath: "/tmp/photo-upscaled-x4.png")
        let edited = OutputWriter.resolveEditedURL(source: src)
        XCTAssertEqual(edited.lastPathComponent, "photo-upscaled-x4-edited.png")
    }

    func testResolveEditedURL_collisionAutoIncrement() throws {
        // Create a temp directory + pre-occupy the `-edited` slot to force
        // auto-increment.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("eraser-collision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let src = tmp.appendingPathComponent("photo.png")
        let editedFirst = tmp.appendingPathComponent("photo-edited.png")
        try Data([0x89]).write(to: editedFirst)

        let next = OutputWriter.resolveEditedURL(source: src)
        XCTAssertEqual(next.lastPathComponent, "photo-edited-2.png")
    }
}
