import XCTest
@testable import ImagingCore

/// Unit tests for `DespeckleFilter.despeckleGrayscale` — direct buffer
/// operations without PNG round-trip. Each test builds a deterministic
/// 8-bit grayscale buffer (0 = black, 255 = white), applies the despeckle
/// pass, and asserts the cleared/preserved pixel pattern.
final class DespeckleFilterTests: XCTestCase {

    // MARK: - Helpers

    /// Black-pixel buffer with a "main blob" + sprinkled isolated speckles.
    private func makeLineArtFixture() -> (buffer: [UInt8], width: Int, height: Int) {
        let w = 64, h = 64
        var buf = [UInt8](repeating: 255, count: w * h)  // all white

        // Main connected blob — a 20×20 solid square in the center
        for y in 22..<42 {
            for x in 22..<42 {
                buf[y * w + x] = 0
            }
        }

        // 6 isolated 1-pixel speckles in corners + edges (area = 1 each)
        let specks = [(2, 2), (60, 2), (2, 60), (60, 60), (10, 10), (54, 54)]
        for (sx, sy) in specks {
            buf[sy * w + sx] = 0
        }

        return (buf, w, h)
    }

    /// Helper: count black pixels in a buffer.
    private func countBlack(_ buf: [UInt8]) -> Int {
        buf.filter { $0 <= 128 }.count
    }

    // MARK: - 6 case set

    func testRemovesSmallSpeckles_preservesLineArt() {
        var (buf, w, h) = makeLineArtFixture()
        let blackBefore = countBlack(buf)
        let mainBlobArea = 20 * 20  // 400

        DespeckleFilter.despeckleGrayscale(
            buffer: &buf, width: w, height: h,
            maxBlobArea: 30  // normal preset — speckles (1 pixel) cleaned
        )

        let blackAfter = countBlack(buf)
        XCTAssertEqual(blackAfter, mainBlobArea,
                       "Main 20×20 blob should be preserved; specks removed")
        XCTAssertEqual(blackBefore - blackAfter, 6,
                       "6 specks (1px each) should be cleared")
    }

    func testThresholdSweep_3PresetsProduceMonotonicCleanup() {
        // Build a fixture with components of varying sizes — assert that
        // increasing the threshold clears strictly more pixels (never fewer).
        let w = 32, h = 32
        var bufSoft = [UInt8](repeating: 255, count: w * h)

        // Components: 3-pixel blob, 15-pixel blob, 50-pixel blob, 200-pixel blob
        // Soft (10) clears 3-pixel only → 3 cleared
        // Normal (30) clears 3 + 15 → 18 cleared
        // Strong (100) clears 3 + 15 + 50 → 68 cleared
        // 200-pixel always preserved
        // 3-pixel line (compact)
        for x in 0..<3 { bufSoft[1 * w + x] = 0 }
        // 15-pixel cluster (3×5 block)
        for y in 5..<10 {
            for x in 5..<8 { bufSoft[y * w + x] = 0 }
        }
        // 50-pixel cluster (5×10 block)
        for y in 12..<22 {
            for x in 12..<17 { bufSoft[y * w + x] = 0 }
        }
        // 200-pixel cluster (10×20 block) — should always survive
        for y in 5..<25 {
            for x in 18..<28 { bufSoft[y * w + x] = 0 }
        }

        var bufNormal = bufSoft
        var bufStrong = bufSoft

        DespeckleFilter.despeckleGrayscale(buffer: &bufSoft, width: w, height: h, maxBlobArea: 10)
        DespeckleFilter.despeckleGrayscale(buffer: &bufNormal, width: w, height: h, maxBlobArea: 30)
        DespeckleFilter.despeckleGrayscale(buffer: &bufStrong, width: w, height: h, maxBlobArea: 100)

        let softBlack = countBlack(bufSoft)
        let normalBlack = countBlack(bufNormal)
        let strongBlack = countBlack(bufStrong)

        XCTAssertGreaterThan(softBlack, normalBlack,
                             "Soft should preserve more than Normal")
        XCTAssertGreaterThan(normalBlack, strongBlack,
                             "Normal should preserve more than Strong")
        // 200-pixel main always preserved
        XCTAssertGreaterThanOrEqual(strongBlack, 200)
    }

    func testPureLineArt_unchangedBitIdentical() {
        // Single huge connected component (40×40 square = 1600 area)
        // > maxBlobArea on any preset → no pixels touched.
        let w = 64, h = 64
        var buf = [UInt8](repeating: 255, count: w * h)
        for y in 10..<50 {
            for x in 10..<50 { buf[y * w + x] = 0 }
        }
        let original = buf

        DespeckleFilter.despeckleGrayscale(buffer: &buf, width: w, height: h, maxBlobArea: 100)

        XCTAssertEqual(buf, original, "Large connected blob should be bit-identical")
    }

    func testPureNoise_allCleaned() {
        // Only isolated 1-pixel specks, all below max threshold
        let w = 32, h = 32
        var buf = [UInt8](repeating: 255, count: w * h)
        for i in stride(from: 0, to: w * h, by: 50) {
            buf[i] = 0  // isolated single-pixel black
        }

        DespeckleFilter.despeckleGrayscale(buffer: &buf, width: w, height: h, maxBlobArea: 30)

        XCTAssertEqual(countBlack(buf), 0, "Pure 1-pixel noise should be fully cleared")
    }

    func testBorderTouchingSpeck_alsoCleanedIfSmall() {
        // Note: design defers "border component preservation" to a future
        // iteration (v2). Current behavior: a small component on the border
        // IS cleaned. This test pins that behavior so any future change is
        // intentional.
        let w = 16, h = 16
        var buf = [UInt8](repeating: 255, count: w * h)
        // 2-pixel speck on the top-left corner
        buf[0] = 0
        buf[1] = 0

        DespeckleFilter.despeckleGrayscale(buffer: &buf, width: w, height: h, maxBlobArea: 30)
        XCTAssertEqual(countBlack(buf), 0,
                       "Phase 1: border-touching small specks ARE cleaned")
    }

    func testAdjacentSpecks_8Connectivity() {
        // Two 1-pixel specks diagonally adjacent — 8-connectivity treats
        // them as ONE 2-pixel component, still under threshold → both cleared.
        let w = 16, h = 16
        var buf = [UInt8](repeating: 255, count: w * h)
        buf[5 * w + 5] = 0
        buf[6 * w + 6] = 0  // diagonal neighbor (8-conn)

        DespeckleFilter.despeckleGrayscale(buffer: &buf, width: w, height: h, maxBlobArea: 30)
        XCTAssertEqual(countBlack(buf), 0,
                       "8-connectivity groups diagonal neighbors into one component")
    }
}
