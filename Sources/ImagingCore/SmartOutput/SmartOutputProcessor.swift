import Foundation

/// Post-upscale PNG optimizer.
///
/// Runs after the engine has written PNG bytes to disk. Detects content
/// type (`ContentDetector`), then chains the appropriate optimizer(s):
///
/// | Mode      | Detection           | Pipeline                      |
/// |-----------|---------------------|-------------------------------|
/// | `.off`    | —                   | (no-op)                       |
/// | `.auto`   | low-entropy detect  | pngquant → oxipng             |
/// | `.auto`   | high-entropy detect | oxipng only (lossless)        |
/// | `.always` | (skipped)           | pngquant → oxipng             |
///
/// **Size-delta guard:** if optimized result is >90% of original size,
/// discard it and keep the original. Catches false positives + guarantees
/// "Smart Output ON" never produces a larger file than "Smart Output OFF".
///
/// **Missing binaries:** in `.auto` mode degrades gracefully (skip,
/// `skipReason="no-binary"`). In `.always` mode throws `.binaryMissing`
/// so preflight surfaces the error.
public struct SmartOutputProcessor: Sendable {
    public init() {}

    public struct ProcessResult: Sendable, Equatable {
        public let originalBytes: Int
        public let finalBytes: Int
        public let wasQuantized: Bool
        public let wasOptimized: Bool
        public let skipReason: String?  // nil = ran; otherwise "mode-off"/"no-binary"/"delta-guard"/"detect-failed"
        public let analysis: ContentDetector.Analysis?

        /// Convenience — `1.0` means no reduction; `0.2` means 5× reduction.
        public var sizeRatio: Double {
            guard originalBytes > 0 else { return 1.0 }
            return Double(finalBytes) / Double(originalBytes)
        }
    }

    public enum SmartOutputError: Error, Equatable {
        case binaryMissing(String)
        case quantizeFailed(stderr: String)
        case optimizeFailed(stderr: String)
        case ioError(String)
    }

    /// The size-delta guard: any result that isn't at least this much smaller
    /// than the original is discarded. 0.90 = "must be at least 10% smaller".
    public static let sizeDeltaThreshold: Double = 0.90

    /// pngquant quality range. Lower bound 65 = "discard quantization below
    /// this quality"; upper bound 100 = best possible. Together: try to
    /// preserve quality ≥65, fail if not possible (handled by `pngquant`
    /// itself — exit code 99 means "couldn't quantize at requested quality").
    public static let pngquantQualityRange = "65-100"

    /// Optimize the PNG at `url` in-place. On success the file at `url` is
    /// replaced; on no-op or skip it is left untouched.
    public func process(url: URL, mode: SmartOutputMode) throws -> ProcessResult {
        let originalBytes = fileSize(at: url)

        // Mode `.off` — no-op.
        if mode == .off {
            return ProcessResult(
                originalBytes: originalBytes,
                finalBytes: originalBytes,
                wasQuantized: false,
                wasOptimized: false,
                skipReason: "mode-off",
                analysis: nil
            )
        }

        // Locate binaries. Behavior on missing depends on mode.
        let pngquantURL = SmartOutputLocator.pngquantURL()
        let oxipngURL = SmartOutputLocator.oxipngURL()

        if pngquantURL == nil || oxipngURL == nil {
            if mode == .always {
                let missing = pngquantURL == nil ? "pngquant" : "oxipng"
                throw SmartOutputError.binaryMissing(missing)
            }
            // `.auto` — graceful degrade.
            return ProcessResult(
                originalBytes: originalBytes,
                finalBytes: originalBytes,
                wasQuantized: false,
                wasOptimized: false,
                skipReason: "no-binary",
                analysis: nil
            )
        }

        // Detect content. In `.always` we skip detection (force quantize).
        var shouldQuantize: Bool
        var analysis: ContentDetector.Analysis? = nil
        switch mode {
        case .always:
            shouldQuantize = true
        case .auto:
            analysis = ContentDetector.analyze(pngURL: url)
            if let a = analysis {
                shouldQuantize = a.isLowEntropy
            } else {
                // Detection failed — fall back to oxipng-only (still safe).
                shouldQuantize = false
            }
        case .off:
            preconditionFailure("Unreachable — handled above")
        }

        // Stage into a tmp file so the original is recoverable if the
        // post-process result fails the size-delta guard.
        let parent = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let tmpURL = parent.appendingPathComponent(".\(stem).smartout.\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        var wasQuantized = false
        if shouldQuantize {
            // pngquant input → tmp. Exit 99 = "quality too low even at min"
            // — recover by falling through to lossless-only.
            let exitCode = runPngquant(
                binary: pngquantURL!,
                input: url,
                output: tmpURL
            )
            if exitCode == 0 {
                wasQuantized = true
            } else if exitCode == 99 {
                // pngquant gave up — copy original to tmp for oxipng input.
                try copyFile(from: url, to: tmpURL)
            } else {
                throw SmartOutputError.quantizeFailed(
                    stderr: "pngquant exit \(exitCode)"
                )
            }
        } else {
            // No quantization — feed original to oxipng directly.
            try copyFile(from: url, to: tmpURL)
        }

        // oxipng in-place on tmp.
        let oxiExit = runOxipng(binary: oxipngURL!, target: tmpURL)
        if oxiExit != 0 {
            throw SmartOutputError.optimizeFailed(
                stderr: "oxipng exit \(oxiExit)"
            )
        }

        let candidateBytes = fileSize(at: tmpURL)
        let ratio = originalBytes > 0
            ? Double(candidateBytes) / Double(originalBytes)
            : 1.0

        // Size-delta guard.
        if ratio > Self.sizeDeltaThreshold {
            return ProcessResult(
                originalBytes: originalBytes,
                finalBytes: originalBytes,
                wasQuantized: wasQuantized,
                wasOptimized: true,
                skipReason: "delta-guard",
                analysis: analysis
            )
        }

        // Promote tmp → url.
        try replace(at: url, with: tmpURL)
        return ProcessResult(
            originalBytes: originalBytes,
            finalBytes: candidateBytes,
            wasQuantized: wasQuantized,
            wasOptimized: true,
            skipReason: nil,
            analysis: analysis
        )
    }

    // MARK: - Subprocess runners (mirror NcnnEngine.runSubprocess pattern)

    private func runPngquant(binary: URL, input: URL, output: URL) -> Int32 {
        let p = Process()
        p.executableURL = binary
        p.arguments = [
            "--speed", "1",
            "--quality", Self.pngquantQualityRange,
            "--output", output.path,
            "--force",
            input.path,
        ]
        // Suppress chatter on stdout/stderr — we only care about exit code.
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    private func runOxipng(binary: URL, target: URL) -> Int32 {
        let p = Process()
        p.executableURL = binary
        p.arguments = [
            "--opt", "6",
            target.path,  // oxipng overwrites in-place by default
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    // MARK: - File helpers

    private func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? Int) ?? 0
    }

    private func copyFile(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        do {
            try fm.copyItem(at: src, to: dst)
        } catch {
            throw SmartOutputError.ioError("copy: \(error.localizedDescription)")
        }
    }

    private func replace(at dst: URL, with src: URL) throws {
        let fm = FileManager.default
        do {
            // Atomic same-volume rename. Both files are in `dst.parent`.
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.moveItem(at: src, to: dst)
        } catch {
            throw SmartOutputError.ioError("replace: \(error.localizedDescription)")
        }
    }
}
