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

    func testDirectColors8Mode_triggersDespeckle() {
        XCTAssertTrue(SmartOutputProcessor.shouldDespeckle(
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

    func testAdaptive_pickedColors8_triggers() {
        XCTAssertTrue(SmartOutputProcessor.shouldDespeckle(
            mode: .adaptive, adaptivePicked: .colors8,
            fingerprint: mockFingerprint(nearBinary: 0.92)
        ))
    }

    func testAdaptive_pickedSoftLoss_butNearBinaryHigh_triggers() {
        // Edge case: classifier picked softLoss but content is actually
        // near-binary. Defensive trigger kicks in.
        XCTAssertTrue(SmartOutputProcessor.shouldDespeckle(
            mode: .adaptive, adaptivePicked: .softLoss,
            fingerprint: mockFingerprint(nearBinary: 0.90)
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
