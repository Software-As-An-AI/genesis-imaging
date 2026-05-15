import XCTest
@testable import ImagingCore

/// Tests for `SmartOutputProcessor.shouldDespeckle(mode:adaptivePicked:
/// fingerprint:)` — the pure predicate that decides whether the despeckle
/// pass runs. Covers the content-guard logic without needing PNG fixtures.
final class DespeckleTriggerLogicTests: XCTestCase {

    private func mockFingerprint(nearBinary: Double) -> ContentFingerprint {
        ContentFingerprint(
            uniqueColorCount: 4,
            nearBinaryScore: nearBinary,
            saturationScore: 0.0,
            edgeDensityScore: 0.5,
            sampledPixels: 100
        )
    }

    // MARK: - Direct mode (manual user choice)

    func testDirectBinarizeMode_triggersDespeckle() {
        XCTAssertTrue(SmartOutputProcessor.shouldDespeckle(
            mode: .binarize, adaptivePicked: nil, fingerprint: nil
        ))
    }

    func testDirectColors8Mode_skipsDespeckle_v0331() {
        // v0.3.3.1: colors8/lineart preserves anti-aliasing — despeckle
        // here destroys character detail. Excluded from triggers.
        XCTAssertFalse(SmartOutputProcessor.shouldDespeckle(
            mode: .colors8, adaptivePicked: nil, fingerprint: nil
        ))
    }

    func testDirectAutoMode_skipsDespeckle() {
        XCTAssertFalse(SmartOutputProcessor.shouldDespeckle(
            mode: .auto, adaptivePicked: nil, fingerprint: nil
        ))
    }

    func testDirectSoftLossMode_skipsDespeckle() {
        XCTAssertFalse(SmartOutputProcessor.shouldDespeckle(
            mode: .softLoss, adaptivePicked: nil, fingerprint: nil
        ))
    }

    func testDirectColors32Mode_skipsDespeckle() {
        XCTAssertFalse(SmartOutputProcessor.shouldDespeckle(
            mode: .colors32, adaptivePicked: nil, fingerprint: nil
        ))
    }

    // MARK: - Adaptive mode (auto-routed by ContentClassifier)

    func testAdaptive_pickedBinarize_triggers() {
        XCTAssertTrue(SmartOutputProcessor.shouldDespeckle(
            mode: .adaptive, adaptivePicked: .binarize,
            fingerprint: mockFingerprint(nearBinary: 0.99)
        ))
    }

    func testAdaptive_pickedColors8_skips_v0331() {
        // v0.3.3.1: even adaptive picker route via colors8 = no despeckle
        // (preserves anti-aliasing path)
        XCTAssertFalse(SmartOutputProcessor.shouldDespeckle(
            mode: .adaptive, adaptivePicked: .colors8,
            fingerprint: mockFingerprint(nearBinary: 0.92)
        ))
    }

    func testAdaptive_pickedSoftLoss_evenNearBinary09_skips_v0331() {
        // v0.3.3.1: defensive threshold raised 0.85 → 0.95. nearBinary=0.90
        // no longer triggers — only very high confidence binary content.
        XCTAssertFalse(SmartOutputProcessor.shouldDespeckle(
            mode: .adaptive, adaptivePicked: .softLoss,
            fingerprint: mockFingerprint(nearBinary: 0.90)
        ))
    }

    func testAdaptive_pickedSoftLoss_veryHighNearBinary_stillTriggers() {
        // 0.95+ defensive trigger still kicks in for misclassified B/W
        XCTAssertTrue(SmartOutputProcessor.shouldDespeckle(
            mode: .adaptive, adaptivePicked: .softLoss,
            fingerprint: mockFingerprint(nearBinary: 0.97)
        ))
    }

    func testAdaptive_pickedAuto_lowNearBinary_skips() {
        // Photo content → adaptive auto + low binarity → no despeckle
        XCTAssertFalse(SmartOutputProcessor.shouldDespeckle(
            mode: .adaptive, adaptivePicked: .auto,
            fingerprint: mockFingerprint(nearBinary: 0.20)
        ))
    }

    func testAdaptive_noFingerprint_pickedAuto_skips() {
        // Defensive: no fingerprint AND no B/W pick → skip
        XCTAssertFalse(SmartOutputProcessor.shouldDespeckle(
            mode: .adaptive, adaptivePicked: .auto, fingerprint: nil
        ))
    }
}
