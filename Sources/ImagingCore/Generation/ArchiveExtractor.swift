import Foundation
import CryptoKit

/// Post-download verification + extraction for SDXL bundles.
///
/// Two responsibilities, both pre-conditions for marking the bundle "ready":
///   1. SHA256 streaming verify against `SDXLModelCatalog.Variant.sha256`
///      (avoids loading 6.71 GB into memory)
///   2. Unzip via `/usr/bin/unzip` Process — macOS-shipped, no SwiftPM
///      dep added (would need `ZIPFoundation` otherwise)
///
/// Disk-space precheck: requires `2 × expectedSize` free (zip + extracted
/// dirs co-exist briefly before zip cleanup).
public enum ArchiveExtractor {

    public enum ExtractError: Error, Equatable, CustomStringConvertible {
        case sha256Mismatch(expected: String, actual: String)
        case insufficientDiskSpace(neededBytes: Int64, freeBytes: Int64)
        case unzipFailed(exitCode: Int32, stderr: String)
        case ioError(String)

        public var description: String {
            switch self {
            case .sha256Mismatch(let exp, let got):
                return "SHA256 mismatch — expected \(exp), got \(got)"
            case .insufficientDiskSpace(let need, let free):
                let needGB = Double(need) / 1_000_000_000
                let freeGB = Double(free) / 1_000_000_000
                return String(format: "Disk space yetersiz — gerekli %.1f GB, boş %.1f GB", needGB, freeGB)
            case .unzipFailed(let code, let stderr):
                return "Unzip failed (exit \(code)): \(stderr)"
            case .ioError(let m):
                return m
            }
        }
    }

    /// Verify zip SHA256 matches expected, then unzip into destination dir.
    /// Caller owns the zip file's lifecycle (this function does not delete it).
    ///
    /// - Parameters:
    ///   - zipURL: local file URL to verify + extract
    ///   - expectedSHA256: hex string (lowercase, 64 chars) — `nil` skips verify
    ///     (used for variants whose SHA hasn't been pinned yet; not recommended)
    ///   - destinationDir: target dir for extracted contents; created if missing
    ///   - expectedSizeBytes: for disk space precheck (zip + extracted concurrent)
    public static func verifyAndExtract(
        zipURL: URL,
        expectedSHA256: String?,
        destinationDir: URL,
        expectedSizeBytes: Int64
    ) throws {
        try checkDiskSpace(destinationDir: destinationDir, neededBytes: expectedSizeBytes * 2)

        if let expected = expectedSHA256 {
            let actual = try streamingSHA256(of: zipURL)
            guard actual.lowercased() == expected.lowercased() else {
                throw ExtractError.sha256Mismatch(expected: expected, actual: actual)
            }
        }

        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        try runUnzip(zipURL: zipURL, destDir: destinationDir)
    }

    /// Streaming SHA256 — reads `zipURL` in 1 MB chunks, keeps memory flat.
    public static func streamingSHA256(of zipURL: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: zipURL) else {
            throw ExtractError.ioError("Cannot open file for reading: \(zipURL.path)")
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1 << 20 // 1 MB
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func checkDiskSpace(destinationDir: URL, neededBytes: Int64) throws {
        // Walk up parent dirs until we find one that exists, then check its volume.
        var probe = destinationDir
        while !FileManager.default.fileExists(atPath: probe.path) {
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path { break }
            probe = parent
        }
        do {
            let values = try probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                            .volumeAvailableCapacityKey])
            let free = (values.volumeAvailableCapacityForImportantUsage)
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            guard free >= neededBytes else {
                throw ExtractError.insufficientDiskSpace(neededBytes: neededBytes, freeBytes: free)
            }
        } catch let e as ExtractError {
            throw e
        } catch {
            // If we can't query (e.g. unusual volume), let extraction proceed
            // — `unzip` itself surfaces ENOSPC if it actually runs out.
        }
    }

    private static func runUnzip(zipURL: URL, destDir: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", zipURL.path, "-d", destDir.path]
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        do {
            try proc.run()
        } catch {
            throw ExtractError.ioError("unzip launch failed: \(error.localizedDescription)")
        }
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let stderr = String(data: stderrData, encoding: .utf8) ?? "<unreadable>"
            throw ExtractError.unzipFailed(exitCode: proc.terminationStatus, stderr: stderr)
        }
    }
}
