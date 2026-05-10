import XCTest
@testable import NcnnEngine

final class ProgressParserTests: XCTestCase {
    private final class Captured: @unchecked Sendable {
        private let queue = DispatchQueue(label: "captured")
        private var values: [Double] = []
        func append(_ v: Double) { queue.sync { self.values.append(v) } }
        var snapshot: [Double] { queue.sync { self.values } }
    }

    func testParseSinglePercentLine() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        parser.feed("25.00%\n")
        XCTAssertEqual(captured.snapshot, [0.25])
    }

    func testParseMultipleLines() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        parser.feed("0.00%\n25.00%\n50.00%\n75.00%\n100.00%\n")
        XCTAssertEqual(captured.snapshot, [0.0, 0.25, 0.5, 0.75, 1.0])
    }

    func testIgnoreNonPercentLine() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        parser.feed("[0 Apple M4 Pro]  queueC=0[1]\n")
        parser.feed("bugsbn1=0  bugbilz=121\n")
        XCTAssertEqual(captured.snapshot, [])
    }

    func testInterleavedHeaderAndProgress() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        parser.feed("""
        [0 Apple M4 Pro]  queueC=0[1]  queueG=0[1]
        [0 Apple M4 Pro]  fp16-p/s/a=1/1/1
        0.00%
        25.00%
        50.00%

        """)
        XCTAssertEqual(captured.snapshot, [0.0, 0.25, 0.5])
    }

    func testChunkedInputAcrossBoundaries() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        // "12.50%\n" arrives split across three feeds
        parser.feed("12.")
        parser.feed("50")
        parser.feed("%\n")
        XCTAssertEqual(captured.snapshot, [0.125])
    }

    func testFlushPicksUpTrailingFragmentWithPercentSign() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        // No trailing newline — only flush() should parse it
        parser.feed("87.50%")
        XCTAssertEqual(captured.snapshot, [], "no newline → no emit until flush")
        parser.flush()
        XCTAssertEqual(captured.snapshot, [0.875])
    }

    func testInvalidPercentageStringIsIgnored() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        parser.feed("not-a-number%\n")
        parser.feed("%\n")
        parser.feed("\n")
        XCTAssertEqual(captured.snapshot, [])
    }

    func testWhitespaceIsTolerated() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        parser.feed("  42.00%  \n")
        XCTAssertEqual(captured.snapshot, [0.42])
    }

    func testValuesAreClampedToZeroOneRange() {
        let captured = Captured()
        let parser = ProgressParser { captured.append($0) }
        parser.feed("-5.0%\n")
        parser.feed("150.0%\n")
        XCTAssertEqual(captured.snapshot, [0.0, 1.0])
    }
}
