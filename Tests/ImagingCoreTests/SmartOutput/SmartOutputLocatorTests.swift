import XCTest
@testable import ImagingCore

final class SmartOutputLocatorTests: XCTestCase {

    func testLocatorReturnsNilOrExecutableURL() {
        // Lookup must either find an existing executable or return nil — never
        // return a URL pointing to a non-executable file.
        if let url = SmartOutputLocator.pngquantURL() {
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: url.path),
                "pngquantURL() returned non-executable path: \(url.path)"
            )
        }
        if let url = SmartOutputLocator.oxipngURL() {
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: url.path),
                "oxipngURL() returned non-executable path: \(url.path)"
            )
        }
    }

    func testBothAvailableMatchesIndividualLookups() {
        let both = SmartOutputLocator.bothAvailable()
        let individual = SmartOutputLocator.pngquantURL() != nil
                      && SmartOutputLocator.oxipngURL() != nil
        XCTAssertEqual(both, individual)
    }
}
