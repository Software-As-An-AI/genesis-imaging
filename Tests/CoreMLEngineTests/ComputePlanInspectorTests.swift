import XCTest
@testable import CoreMLEngine
import ImagingCore

/// `MLComputePlan` is only available macOS 14.4+. Tests guard with the same
/// availability annotation; on older OS the test simply skips.
@available(macOS 14.4, *)
final class ComputePlanInspectorTests: XCTestCase {

    /// True when the bundled Core ML model can be located.
    private func modelAvailable() -> Bool {
        (try? ModelLocator.defaultModelURL()) != nil
    }

    func test_summarize_reports_layer_distribution() async throws {
        try XCTSkipUnless(modelAvailable(), "Core ML model not bundled — run scripts/fetch-coreml-model.sh")

        let modelURL = try ModelLocator.defaultModelURL()
        let summary = try await ComputePlanInspector.summarize(modelURL: modelURL)

        XCTAssertGreaterThan(summary.totalLayers, 0, "expected at least one layer")
        // Sanity: counts add up to total
        let sum = summary.aneCount + summary.gpuCount + summary.cpuCount + summary.unknownCount
        XCTAssertEqual(sum, summary.totalLayers,
                       "ANE+GPU+CPU+unknown must equal total layers")
        // Real-ESRGAN x4plus is heavily Conv2D — at least one device should be preferred
        XCTAssertGreaterThan(summary.aneCount + summary.gpuCount + summary.cpuCount, 0,
                             "expected at least some layers assigned")

        // Log the summary so we can read it in test output even when assertions pass
        print("\n[compute-plan] \(ComputePlanInspector.formatSummary(summary))\n")
    }

    func test_formatSummary_includesAllDevices() {
        let summary = ComputePlanInspector.DeviceUsageSummary(
            totalLayers: 100,
            aneCount: 70,
            gpuCount: 25,
            cpuCount: 5,
            unknownCount: 0
        )
        let formatted = ComputePlanInspector.formatSummary(summary)
        XCTAssertTrue(formatted.contains("ANE 70"))
        XCTAssertTrue(formatted.contains("GPU 25"))
        XCTAssertTrue(formatted.contains("CPU 5"))
        XCTAssertTrue(formatted.contains("ane-dominant"))
    }

    func test_verdict_thresholds() {
        XCTAssertEqual(
            ComputePlanInspector.DeviceUsageSummary(totalLayers: 100, aneCount: 51, gpuCount: 30, cpuCount: 19, unknownCount: 0).verdict,
            .aneDominant
        )
        XCTAssertEqual(
            ComputePlanInspector.DeviceUsageSummary(totalLayers: 100, aneCount: 30, gpuCount: 51, cpuCount: 19, unknownCount: 0).verdict,
            .gpuDominant
        )
        XCTAssertEqual(
            ComputePlanInspector.DeviceUsageSummary(totalLayers: 100, aneCount: 30, gpuCount: 30, cpuCount: 40, unknownCount: 0).verdict,
            .mixed
        )
        XCTAssertEqual(
            ComputePlanInspector.DeviceUsageSummary(totalLayers: 0, aneCount: 0, gpuCount: 0, cpuCount: 0, unknownCount: 0).verdict,
            .unsupported
        )
    }
}
