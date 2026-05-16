import Foundation

// MARK: - OutputWriter

/// Resolves output filenames + writes upscaled bytes atomically.
///
/// Resolution rules (per plan §3 + §4 Phase D):
/// - `batchOverride == nil` → same directory as source, suffix `-upscaled-x{scale}`,
///   preserve original extension.
/// - `batchOverride != nil` → directory replaced; basename + suffix + ext as above.
///
/// Conflict policy: if the resolved URL already exists, append `-2`, `-3`, ...
/// until an unused name is found. Resolution is read-only on disk (uses
/// `FileManager.fileExists`); no probe writes.
///
/// Atomic write: bytes are first written to `<final>.tmp.<uuid>` and then
/// moved into place via `FileManager.moveItem(at:to:)`. On any failure the
/// tmp file is cleaned up before rethrowing.
public enum OutputWriter {

    /// Errors produced by `atomicWrite`. Resolution itself doesn't throw —
    /// it only inspects the filesystem.
    public enum WriteError: Error, Equatable {
        case tmpWriteFailed(URL, underlying: String)
        case renameFailed(from: URL, to: URL, underlying: String)
        case destinationParentMissing(URL)
        case destinationNotWritable(URL)
    }

    // MARK: - Resolution

    /// Resolve the final output URL for `source` at `scale`, honoring an
    /// optional batch override directory.
    ///
    /// Filename pattern: `<basename>-upscaled-x<scale>.<ext>`. On conflict,
    /// append `-2`, `-3`, ... before the extension until an unused name is
    /// found.
    ///
    /// - Parameters:
    ///   - source: Input image URL (used for basename + parent dir + ext).
    ///   - scale: Upscale factor (e.g. 2, 3, 4).
    ///   - batchOverride: When non-nil, place output in this directory
    ///     (parent of `source` is ignored).
    /// - Returns: Final URL guaranteed not to exist at call time.
    public static func resolveOutputURL(
        source: URL,
        scale: Int,
        batchOverride: URL?,
        smartOutputTag: String? = nil
    ) -> URL {
        let parent = (batchOverride ?? source.deletingLastPathComponent())
            .standardizedFileURL
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        let tagSuffix = smartOutputTag.map { "-\($0)" } ?? ""
        let baseStem = "\(stem)-upscaled-x\(scale)\(tagSuffix)"

        let first = parent.appendingPathComponent(baseStem)
            .appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: first.path) {
            return first
        }

        // Auto-increment loop. Cap at a large but finite count so a runaway
        // never spins forever (defensive).
        var counter = 2
        while counter < 10_000 {
            let candidate = parent.appendingPathComponent("\(baseStem)-\(counter)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
        return parent.appendingPathComponent("\(baseStem)-\(counter)")
            .appendingPathExtension(ext)
    }

    /// Resolve a destination URL for an "edited" variant of `source` — same
    /// directory, same extension, stem suffixed with `-edited`. On collision,
    /// auto-increment as `-edited-2`, `-edited-3`, ... Used by the manual
    /// eraser brush "Save as new file" flow.
    public static func resolveEditedURL(source: URL) -> URL {
        let dir = source.deletingLastPathComponent().standardizedFileURL
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        let baseStem = "\(stem)-edited"

        let first = dir.appendingPathComponent(baseStem)
            .appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: first.path) {
            return first
        }
        var counter = 2
        while counter < 10_000 {
            let candidate = dir.appendingPathComponent("\(baseStem)-\(counter)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
        return dir.appendingPathComponent("\(baseStem)-\(counter)")
            .appendingPathExtension(ext)
    }

    // MARK: - Atomic Write

    /// Write `data` to `url` atomically via tmp-then-rename.
    ///
    /// On macOS, `FileManager.moveItem(at:to:)` is atomic when both ends are
    /// on the same volume (rename(2) syscall). The tmp file lives in the
    /// **same directory** as the destination to guarantee that.
    ///
    /// - Throws: `WriteError.destinationParentMissing` if the parent directory
    ///   doesn't exist; `WriteError.tmpWriteFailed` if the initial write fails;
    ///   `WriteError.renameFailed` if the move fails (tmp is cleaned up first).
    public static func atomicWrite(data: Data, to url: URL) throws {
        let final = url.standardizedFileURL
        let parent = final.deletingLastPathComponent()
        let fm = FileManager.default

        guard fm.fileExists(atPath: parent.path) else {
            throw WriteError.destinationParentMissing(parent)
        }
        guard fm.isWritableFile(atPath: parent.path) else {
            throw WriteError.destinationNotWritable(parent)
        }

        let tmp = parent.appendingPathComponent(
            "\(final.lastPathComponent).tmp.\(UUID().uuidString)"
        )

        do {
            try data.write(to: tmp, options: [.atomic])
        } catch {
            // No tmp to clean up — `.atomic` write either succeeded or wrote nothing.
            throw WriteError.tmpWriteFailed(tmp, underlying: error.localizedDescription)
        }

        do {
            // If the destination somehow popped up between resolve + write
            // (sequential pipeline makes this rare), prefer overwrite-by-move
            // semantics so caller gets the expected file.
            if fm.fileExists(atPath: final.path) {
                try? fm.removeItem(at: final)
            }
            try fm.moveItem(at: tmp, to: final)
        } catch {
            // Clean up tmp on rename failure so we never leave partial garbage.
            try? fm.removeItem(at: tmp)
            throw WriteError.renameFailed(
                from: tmp,
                to: final,
                underlying: error.localizedDescription
            )
        }

        // Strip quarantine xattr — sandboxed/notarized apps inherit it on
        // every write, which blocks web upload pipelines (Canva, Drive web).
        // See QuarantineUtil for rationale.
        QuarantineUtil.stripQuarantine(at: final)
    }
}
