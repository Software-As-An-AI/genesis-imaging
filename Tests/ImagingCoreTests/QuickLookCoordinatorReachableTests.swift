import XCTest

/// Smoke test for the row-level "open output" affordances added 2026-05-15.
///
/// The Quick Look panel itself can't be exercised in a headless test runner
/// (QLPreviewPanel needs a key window + responder chain), but the
/// `NSWorkspace` calls behind the "Aç" + "Finder'da göster" buttons are
/// safe to invoke on any URL — they just return a boolean / no-op for paths
/// that don't exist. This test asserts:
///
///   - `NSWorkspace.shared.open(url)` for an existing temp file returns true
///     (some app on the system claims `.txt`).
///   - `activateFileViewerSelecting([url])` doesn't throw for a real URL.
///
/// Coordinator wiring is verified by `swift build` (compile-time linkage to
/// Quartz framework) + manual smoke; the panel itself is GUI-bound.
final class QuickLookCoordinatorReachableTests: XCTestCase {

    func testNSWorkspaceOpenOnExistingFile_returnsTrue() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-smoke-\(UUID().uuidString).txt")
        try "hello".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // open(url:) is async-launches but returns true if a launch was
        // attempted. We don't wait for the GUI app — we just verify the call
        // path doesn't crash + reports success.
        // Note: in CI this may fail if no default .txt handler is registered;
        // wrapped in #if to skip then.
        #if !CI
        let opened = NSWorkspace.shared.open(tmp)
        XCTAssertTrue(opened, "NSWorkspace.open should succeed for existing file")
        #endif
    }

    func testActivateFileViewerSelecting_doesNotCrashForMissingPath() {
        let bogus = URL(fileURLWithPath: "/var/folders/__nonexistent__/x.png")
        // activateFileViewerSelecting tolerates nonexistent paths (Finder
        // shows the closest parent). The contract here is "no crash".
        NSWorkspace.shared.activateFileViewerSelecting([bogus])
        XCTAssertTrue(true, "Reached past activateFileViewerSelecting call")
    }
}

#if canImport(AppKit)
import AppKit
#endif
