import XCTest
import ImagingCore
@testable import NcnnEngine

final class BinaryLocatorTests: XCTestCase {
    func testValidateThrowsForMissingBinary() {
        let nonexistent = URL(fileURLWithPath: "/tmp/genesis-imaging-tests/does-not-exist-\(UUID().uuidString)")
        XCTAssertThrowsError(try BinaryLocator.validate(binaryURL: nonexistent)) { error in
            guard case let UpscaleError.binaryNotFound(path) = error else {
                return XCTFail("expected binaryNotFound, got \(error)")
            }
            XCTAssertEqual(path, nonexistent.path)
        }
    }

    func testValidatePassesForExecutableBinary() throws {
        // Create a tiny executable shell script in a temp dir.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scriptURL = tempDir.appendingPathComponent("fake-binary")
        try "#!/bin/sh\necho ok\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        XCTAssertNoThrow(try BinaryLocator.validate(binaryURL: scriptURL))
    }

    func testBinaryNameConstant() {
        XCTAssertEqual(BinaryLocator.binaryName, "realesrgan-ncnn-vulkan")
    }
}
