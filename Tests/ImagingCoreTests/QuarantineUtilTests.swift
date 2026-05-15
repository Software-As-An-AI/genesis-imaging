import XCTest
import Darwin
@testable import ImagingCore

/// Tests for `QuarantineUtil.stripQuarantine(at:)`. Quarantine xattr is set
/// by macOS on every sandboxed-app write — Canva + Drive web upload
/// pipelines refuse such files. Util strips it after each atomic write.
final class QuarantineUtilTests: XCTestCase {

    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("quarantine-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root = tempRoot { try? FileManager.default.removeItem(at: root) }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func hasQuarantine(at url: URL) -> Bool {
        url.path.withCString { cpath in
            let bufSize = 256
            var buf = [CChar](repeating: 0, count: bufSize)
            let rc = getxattr(cpath, "com.apple.quarantine", &buf, bufSize, 0, 0)
            return rc > 0
        }
    }

    private func writeQuarantineXattr(at url: URL, value: String = "0002;test;TestAgent;") {
        let bytes = Array(value.utf8)
        url.path.withCString { cpath in
            _ = bytes.withUnsafeBufferPointer { ptr in
                setxattr(cpath, "com.apple.quarantine",
                         ptr.baseAddress, ptr.count, 0, 0)
            }
        }
    }

    // MARK: - Tests

    func testStrip_removesQuarantineXattr() throws {
        let f = tempRoot.appendingPathComponent("a.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: f)  // PNG magic
        writeQuarantineXattr(at: f)
        XCTAssertTrue(hasQuarantine(at: f), "Test fixture should have xattr set")

        let stripped = QuarantineUtil.stripQuarantine(at: f)
        XCTAssertTrue(stripped, "Strip should report success")
        XCTAssertFalse(hasQuarantine(at: f), "Xattr should be gone after strip")
    }

    func testStrip_isNoOpWhenXattrAbsent() throws {
        // Fresh file, no xattr set — strip should still return true (ENOATTR
        // treated as benign).
        let f = tempRoot.appendingPathComponent("b.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: f)
        XCTAssertFalse(hasQuarantine(at: f))

        let stripped = QuarantineUtil.stripQuarantine(at: f)
        XCTAssertTrue(stripped, "Missing-xattr strip should still report success")
    }

    func testStrip_returnsFalseOnNonexistentPath() {
        let bogus = tempRoot.appendingPathComponent("nope.png")
        let stripped = QuarantineUtil.stripQuarantine(at: bogus)
        XCTAssertFalse(stripped, "Strip on missing file should return false")
    }
}
