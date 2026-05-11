import XCTest
@testable import ImagingCore

final class OutputWriterTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("outputwriter-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Restore writability in case a test toggled it.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tempDir.path
        )
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func touch(_ url: URL, bytes: Int = 4) {
        try? Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    // MARK: - Resolution

    func test_same_dir_suffix_no_conflict() {
        let source = tempDir.appendingPathComponent("photo.png")
        touch(source)
        let resolved = OutputWriter.resolveOutputURL(
            source: source, scale: 4, batchOverride: nil
        )
        XCTAssertEqual(resolved.deletingLastPathComponent().path,
                       tempDir.standardizedFileURL.path,
                       "Resolved URL stays in source's parent when no override")
        XCTAssertEqual(resolved.lastPathComponent, "photo-upscaled-x4.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolved.path))
    }

    func test_batch_override_directory() {
        let source = tempDir.appendingPathComponent("photo.png")
        touch(source)
        let outDir = tempDir.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let resolved = OutputWriter.resolveOutputURL(
            source: source, scale: 2, batchOverride: outDir
        )
        XCTAssertEqual(resolved.deletingLastPathComponent().path,
                       outDir.standardizedFileURL.path,
                       "Batch override sets parent directory")
        XCTAssertEqual(resolved.lastPathComponent, "photo-upscaled-x2.png")
    }

    func test_filename_conflict_increments_to_2_then_3() {
        let source = tempDir.appendingPathComponent("photo.jpg")
        touch(source)
        // Pre-create the natural target.
        let firstName = tempDir.appendingPathComponent("photo-upscaled-x4.jpg")
        touch(firstName)

        let r2 = OutputWriter.resolveOutputURL(source: source, scale: 4, batchOverride: nil)
        XCTAssertEqual(r2.lastPathComponent, "photo-upscaled-x4-2.jpg")

        // Now occupy -2 too.
        touch(r2)
        let r3 = OutputWriter.resolveOutputURL(source: source, scale: 4, batchOverride: nil)
        XCTAssertEqual(r3.lastPathComponent, "photo-upscaled-x4-3.jpg")
    }

    func test_scale_appears_in_basename_when_changed() {
        let source = tempDir.appendingPathComponent("photo.heic")
        touch(source)

        let s2 = OutputWriter.resolveOutputURL(source: source, scale: 2, batchOverride: nil)
        let s3 = OutputWriter.resolveOutputURL(source: source, scale: 3, batchOverride: nil)
        let s4 = OutputWriter.resolveOutputURL(source: source, scale: 4, batchOverride: nil)

        XCTAssertEqual(s2.lastPathComponent, "photo-upscaled-x2.heic")
        XCTAssertEqual(s3.lastPathComponent, "photo-upscaled-x3.heic")
        XCTAssertEqual(s4.lastPathComponent, "photo-upscaled-x4.heic")
    }

    // MARK: - Atomic write

    func test_atomic_write_creates_target_file() throws {
        let target = tempDir.appendingPathComponent("out.png")
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try OutputWriter.atomicWrite(data: bytes, to: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        let read = try Data(contentsOf: target)
        XCTAssertEqual(read, bytes)
    }

    func test_atomic_write_via_tmp_then_rename_no_partial() throws {
        let target = tempDir.appendingPathComponent("out.png")
        let bytes = Data(repeating: 0x42, count: 4096)
        try OutputWriter.atomicWrite(data: bytes, to: target)

        // After write completes, target exists, no orphan tmp.
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let tmpLeaks = contents.filter { $0.contains(".tmp.") }
        XCTAssertEqual(tmpLeaks, [], "No orphan tmp file should remain after successful write")
    }

    func test_atomic_write_overwrites_existing_destination() throws {
        let target = tempDir.appendingPathComponent("out.png")
        try Data([0x01]).write(to: target)
        let newBytes = Data([0x99, 0x99, 0x99])
        try OutputWriter.atomicWrite(data: newBytes, to: target)
        let read = try Data(contentsOf: target)
        XCTAssertEqual(read, newBytes, "Existing target replaced atomically")
    }

    func test_atomic_write_missing_parent_throws_meaningful_error() {
        let missingParent = tempDir.appendingPathComponent("does/not/exist")
        let target = missingParent.appendingPathComponent("out.png")
        XCTAssertThrowsError(try OutputWriter.atomicWrite(data: Data([0x01]), to: target)) { err in
            guard case OutputWriter.WriteError.destinationParentMissing(let url) = err else {
                XCTFail("Expected destinationParentMissing, got \(err)")
                return
            }
            XCTAssertEqual(url.standardizedFileURL.path, missingParent.standardizedFileURL.path)
        }
    }

    func test_read_only_dir_throws_meaningful_error() throws {
        // Drop write perms on parent (keep readable so we can clean up).
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: tempDir.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tempDir.path
            )
        }

        let target = tempDir.appendingPathComponent("out.png")
        XCTAssertThrowsError(try OutputWriter.atomicWrite(data: Data([0x01]), to: target)) { err in
            guard case OutputWriter.WriteError.destinationNotWritable(let url) = err else {
                XCTFail("Expected destinationNotWritable, got \(err)")
                return
            }
            XCTAssertEqual(url.standardizedFileURL.path, tempDir.standardizedFileURL.path)
        }
    }
}
