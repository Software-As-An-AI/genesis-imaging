import XCTest
@testable import ImagingCore

final class CloudLocationDetectorTests: XCTestCase {

    // MARK: - iCloud path heuristics

    func testInspect_classifiesMobileDocumentsAsICloudContainer() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Project/photo.png")
        let v = CloudLocationDetector.inspect(url)
        XCTAssertEqual(v, .iCloudDriveContainer)
        XCTAssertTrue(v.isCloudSynced)
    }

    func testInspect_returnsNonCloudForDownloads() {
        let url = URL(fileURLWithPath: "\(NSHomeDirectory())/Downloads/test.png")
        let v = CloudLocationDetector.inspect(url)
        XCTAssertEqual(v, .nonCloud)
        XCTAssertFalse(v.isCloudSynced)
    }

    func testInspect_returnsNonCloudForTmp() {
        let url = URL(fileURLWithPath: "/tmp/test.png")
        XCTAssertEqual(CloudLocationDetector.inspect(url), .nonCloud)
    }

    func testVerdict_warningMessageEmptyForNonCloud() {
        XCTAssertTrue(CloudLocationDetector.Verdict.nonCloud.warningMessage.isEmpty)
    }

    func testVerdict_warningMessageMentionsRecommendation() {
        let msg = CloudLocationDetector.Verdict.iCloudDriveContainer.warningMessage
        XCTAssertTrue(msg.contains("Downloads"), "Warning should suggest Downloads as alternative")
    }
}

// MARK: - Filename heuristics

final class FilenameHeuristicsTests: XCTestCase {

    func testLooksLikeUpscaled_truePositive() {
        let url = URL(fileURLWithPath: "/x/photo-upscaled-x4.png")
        XCTAssertTrue(FilenameHeuristics.looksLikeAlreadyUpscaled(url))
    }

    func testLooksLikeUpscaled_truePositiveSmartTag() {
        let url = URL(fileURLWithPath: "/x/photo-upscaled-x4-adaptive-binarize.png")
        XCTAssertTrue(FilenameHeuristics.looksLikeAlreadyUpscaled(url))
    }

    func testLooksLikeUpscaled_falsePositiveAvoided() {
        // "upscale" as a marketing word shouldn't trip the heuristic — we
        // require the canonical hyphenated suffix "-upscaled-".
        let url = URL(fileURLWithPath: "/x/upscale_tutorial.png")
        XCTAssertFalse(FilenameHeuristics.looksLikeAlreadyUpscaled(url))
    }

    func testLooksLikeUpscaled_freshFile() {
        let url = URL(fileURLWithPath: "/x/photo.png")
        XCTAssertFalse(FilenameHeuristics.looksLikeAlreadyUpscaled(url))
    }

    func testPartition_splitsCorrectly() {
        let urls = [
            URL(fileURLWithPath: "/x/a.png"),
            URL(fileURLWithPath: "/x/b-upscaled-x4.png"),
            URL(fileURLWithPath: "/x/c.jpg"),
            URL(fileURLWithPath: "/x/d-upscaled-x4-adaptive-lineart.png"),
        ]
        let parts = FilenameHeuristics.partition(urls)
        XCTAssertEqual(parts.fresh.map { $0.lastPathComponent }, ["a.png", "c.jpg"])
        XCTAssertEqual(parts.alreadyUpscaled.map { $0.lastPathComponent },
                       ["b-upscaled-x4.png", "d-upscaled-x4-adaptive-lineart.png"])
    }
}
