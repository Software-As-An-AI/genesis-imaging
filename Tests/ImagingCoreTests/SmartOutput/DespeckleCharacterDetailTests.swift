import XCTest
@testable import ImagingCore

/// Empirical validation of despeckle behavior on character details — the
/// 2026-05-15 Nadezhda customer report observed: "Agresif olunca
/// karakterlerin ağzı yok oldu, normal modda düşük çözünürlüklü pixeller
/// geldi". This test suite pins the algorithm's behavior on synthetic
/// character-detail-sized features so we can reason about preset thresholds.
///
/// Fixture: a "main character body" (large connected blob, ~400 px) +
/// "mouth detail" (smaller isolated feature, ~20 px) + "dust speckle"
/// (very small isolated, ~3 px).
///
/// Hypothesis: at the v0.3.3.0 default thresholds (soft 10 / normal 30 /
/// strong 100), the mouth detail is **destroyed at normal+** because
/// 20 < 30. Customer-observed regression confirmed.
final class DespeckleCharacterDetailTests: XCTestCase {

    /// 64×64 grid:
    ///   - Main body: 20×20 solid blob at center [22..42, 22..42] → 400 px
    ///   - Mouth detail: 4×5 isolated rectangle [50..54, 30..35] → 20 px
    ///   - Dust speckle: single pixel [5, 5] → 1 px
    private func makeCharacterFixture() -> (buffer: [UInt8], width: Int, height: Int) {
        let w = 64, h = 64
        var buf = [UInt8](repeating: 255, count: w * h)
        // Main body
        for y in 22..<42 {
            for x in 22..<42 { buf[y * w + x] = 0 }
        }
        // Mouth detail (isolated 4×5 = 20 px)
        for y in 30..<35 {
            for x in 50..<54 { buf[y * w + x] = 0 }
        }
        // Dust speckle (1 px)
        buf[5 * 64 + 5] = 0
        return (buf, w, h)
    }

    private func countBlack(_ buf: [UInt8]) -> Int { buf.filter { $0 <= 128 }.count }

    // MARK: - Soft preset (threshold 10)

    func testSoftPreset_preservesMouthDetail_clearsDust() {
        var (buf, w, h) = makeCharacterFixture()
        // Pre: 400 + 20 + 1 = 421 black pixels
        XCTAssertEqual(countBlack(buf), 421)

        DespeckleFilter.despeckleGrayscale(
            buffer: &buf, width: w, height: h,
            maxBlobArea: DespecklePreset.soft.maxBlobArea  // 10
        )

        // Soft (10): main body (400) preserved, mouth (20) preserved, dust (1) cleared
        XCTAssertEqual(countBlack(buf), 420,
                       "Soft should preserve mouth + body, clear only dust")
    }

    // MARK: - Normal preset (v0.3.3.1: threshold 8) — REGRESSION FIXED

    func testNormalPreset_preservesMouthDetail_v0331() {
        var (buf, w, h) = makeCharacterFixture()

        DespeckleFilter.despeckleGrayscale(
            buffer: &buf, width: w, height: h,
            maxBlobArea: DespecklePreset.normal.maxBlobArea  // v0.3.3.1: 8
        )

        // v0.3.3.1 fix: Normal (8) preserves 20px mouth + 400 body, clears 1px dust.
        // Pre-fix (v0.3.3.0, threshold 30) destroyed mouth — customer regression.
        XCTAssertEqual(countBlack(buf), 420,
                       "v0.3.3.1: Normal preset preserves 20px mouth detail. " +
                       "Body 400 + mouth 20 = 420 expected.")
    }

    // MARK: - Strong preset (v0.3.3.1: threshold 18) — mouth still preserved

    func testStrongPreset_preservesMouthDetail_v0331() {
        var (buf, w, h) = makeCharacterFixture()

        DespeckleFilter.despeckleGrayscale(
            buffer: &buf, width: w, height: h,
            maxBlobArea: DespecklePreset.strong.maxBlobArea  // v0.3.3.1: 18
        )

        // v0.3.3.1 fix: Strong (18) preserves 20px mouth — was 100 in v0.3.3.0.
        // Mouth (20) > 18 threshold → preserved.
        XCTAssertEqual(countBlack(buf), 420,
                       "v0.3.3.1: Strong preset still preserves 20px mouth (20 > 18). " +
                       "Features smaller than 18px are at risk — by design.")
    }

    // MARK: - Proposed tuning (v0.3.3.1 candidate)

    func testProposedNewThresholds_preserveMouthAtAllPresets() {
        // Customer artifact analysis: ncnn upscale residue is typically
        // 1-5 px isolated dust. Character details (mouth, eyebrow, etc.)
        // are 15-50 px small features. Therefore the threshold should be
        // bounded above by ~10-15 to preserve all features.
        //
        // Proposed: soft 3, normal 8, strong 18 (instead of 10/30/100).
        for threshold in [3, 8, 18] {
            var (buf, w, h) = makeCharacterFixture()
            DespeckleFilter.despeckleGrayscale(
                buffer: &buf, width: w, height: h,
                maxBlobArea: threshold
            )
            // Mouth (20 px) should survive ALL three thresholds.
            // Body (400) + mouth (20) = 420. Dust (1) is always cleared.
            XCTAssertEqual(countBlack(buf), 420,
                           "Proposed threshold \(threshold) should preserve 20px mouth. " +
                           "Body 400 + mouth 20 = 420 expected.")
        }
    }
}
