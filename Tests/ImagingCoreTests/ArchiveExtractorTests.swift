import XCTest
import CryptoKit
@testable import ImagingCore

final class ArchiveExtractorTests: XCTestCase {

    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveExtractorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - SHA256

    func test_streamingSHA256_matchesKnownValue() throws {
        let payload = Data("genesis-imaging".utf8)
        let zipURL = tempRoot.appendingPathComponent("known.bin")
        try payload.write(to: zipURL)

        let actual = try ArchiveExtractor.streamingSHA256(of: zipURL)
        let expected = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actual, expected)
    }

    func test_streamingSHA256_handlesLargeFile() throws {
        // 4 MB random buffer — exercises the streaming chunk loop (chunk=1MB).
        var rng = SystemRandomNumberGenerator()
        var payload = Data(capacity: 4 << 20)
        for _ in 0..<(4 << 18) { // 4 chunks of 1MB worth of UInt64 words
            withUnsafeBytes(of: rng.next()) { payload.append(contentsOf: $0) }
        }
        let url = tempRoot.appendingPathComponent("big.bin")
        try payload.write(to: url)

        let actual = try ArchiveExtractor.streamingSHA256(of: url)
        let expected = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actual, expected)
    }

    // MARK: - SHA mismatch detection

    func test_verifyAndExtract_failsOnSHAMismatch() throws {
        // Make a real zip (system unzip needs valid zip — empty file fails).
        let zipURL = try makeMinimalZip(in: tempRoot, name: "fixture.zip")
        let actualSHA = try ArchiveExtractor.streamingSHA256(of: zipURL)
        let wrongSHA = String(repeating: "0", count: 64)
        XCTAssertNotEqual(actualSHA, wrongSHA, "test setup invariant")

        XCTAssertThrowsError(try ArchiveExtractor.verifyAndExtract(
            zipURL: zipURL,
            expectedSHA256: wrongSHA,
            destinationDir: tempRoot.appendingPathComponent("extract"),
            expectedSizeBytes: 1024
        )) { err in
            guard case ArchiveExtractor.ExtractError.sha256Mismatch(let exp, let got) = err else {
                XCTFail("Expected sha256Mismatch, got \(err)")
                return
            }
            XCTAssertEqual(exp, wrongSHA)
            XCTAssertEqual(got, actualSHA)
        }
    }

    // MARK: - Unzip happy path

    func test_verifyAndExtract_unzipsValidArchive() throws {
        let zipURL = try makeMinimalZip(in: tempRoot, name: "valid.zip")
        let sha = try ArchiveExtractor.streamingSHA256(of: zipURL)
        let destDir = tempRoot.appendingPathComponent("extract")

        try ArchiveExtractor.verifyAndExtract(
            zipURL: zipURL,
            expectedSHA256: sha,
            destinationDir: destDir,
            expectedSizeBytes: 1024
        )

        // Marker file extracted from the fixture zip
        let extractedFile = destDir.appendingPathComponent("marker.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFile.path))
        let content = try String(contentsOf: extractedFile, encoding: .utf8)
        XCTAssertEqual(content, "genesis-imaging-fixture\n")
    }

    func test_verifyAndExtract_skipsVerifyWhenSHAUnpinned() throws {
        let zipURL = try makeMinimalZip(in: tempRoot, name: "unpinned.zip")
        let destDir = tempRoot.appendingPathComponent("extract")

        try ArchiveExtractor.verifyAndExtract(
            zipURL: zipURL,
            expectedSHA256: nil,
            destinationDir: destDir,
            expectedSizeBytes: 1024
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destDir.appendingPathComponent("marker.txt").path))
    }

    // MARK: - Helpers

    /// Build a real (system-zip valid) archive containing `marker.txt`.
    /// Uses `/usr/bin/zip` (macOS-shipped) — same tool family `unzip` reads.
    private func makeMinimalZip(in dir: URL, name: String) throws -> URL {
        let payloadDir = dir.appendingPathComponent("payload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)
        let marker = payloadDir.appendingPathComponent("marker.txt")
        try "genesis-imaging-fixture\n".write(to: marker, atomically: true, encoding: .utf8)

        let zipURL = dir.appendingPathComponent(name)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-j", "-q", zipURL.path, marker.path]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "test.zip", code: Int(proc.terminationStatus))
        }
        try? FileManager.default.removeItem(at: payloadDir)
        return zipURL
    }
}
