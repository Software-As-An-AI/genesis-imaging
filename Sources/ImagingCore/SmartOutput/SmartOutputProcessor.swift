import Foundation

/// Post-upscale PNG optimizer.
///
/// Runs after the engine has written PNG bytes to disk. Operates on a tmp
/// copy so any failure leaves the engine's output intact. Modes:
///
/// | Mode         | Pipeline                                              |
/// |--------------|-------------------------------------------------------|
/// | `.off`       | (no-op)                                               |
/// | `.auto`      | content detect → quantize (Q 65-100) + oxipng         |
/// |              | OR oxipng-only when high-entropy                      |
/// | `.always`    | pngquant Q 65-100 + oxipng                            |
/// | `.softLoss`  | pngquant Q 40-90 + oxipng                             |
/// | `.colors32`  | pngquant 32 colors + oxipng                           |
/// | `.colors8`   | pngquant 8 colors + oxipng                            |
/// | `.binarize`  | pngquant 2 colors + oxipng (saf B/W)                  |
///
/// **Size-delta guard:** if optimized result is >90% of original, discard
/// and keep original (false-positive defense + "never worsen" invariant).
///
/// **Missing binaries:** `.auto` degrades gracefully (skip); other modes
/// throw `.binaryMissing` so the caller can surface a clear error.
public struct SmartOutputProcessor: Sendable {
    public init() {}

    public struct ProcessResult: Sendable, Equatable {
        public let originalBytes: Int
        public let finalBytes: Int
        public let wasQuantized: Bool
        public let wasOptimized: Bool
        public let skipReason: String?
        public let analysis: ContentDetector.Analysis?
        /// When the request was `.adaptive`, this is the concrete sub-mode
        /// the classifier picked (binarize / colors8 / colors32 / softLoss /
        /// auto). Otherwise `nil`.
        public let adaptivePicked: SmartOutputMode?
        /// Full fingerprint computed in `.adaptive` mode (or `nil` for other modes).
        public let fingerprint: ContentFingerprint?

        public var sizeRatio: Double {
            guard originalBytes > 0 else { return 1.0 }
            return Double(finalBytes) / Double(originalBytes)
        }

        public init(
            originalBytes: Int,
            finalBytes: Int,
            wasQuantized: Bool,
            wasOptimized: Bool,
            skipReason: String?,
            analysis: ContentDetector.Analysis?,
            adaptivePicked: SmartOutputMode? = nil,
            fingerprint: ContentFingerprint? = nil
        ) {
            self.originalBytes = originalBytes
            self.finalBytes = finalBytes
            self.wasQuantized = wasQuantized
            self.wasOptimized = wasOptimized
            self.skipReason = skipReason
            self.analysis = analysis
            self.adaptivePicked = adaptivePicked
            self.fingerprint = fingerprint
        }
    }

    public enum SmartOutputError: Error, Equatable {
        case binaryMissing(String)
        case quantizeFailed(stderr: String)
        case optimizeFailed(stderr: String)
        case ioError(String)
    }

    public static let sizeDeltaThreshold: Double = 0.90

    public func process(url: URL, mode: SmartOutputMode) throws -> ProcessResult {
        let originalBytes = fileSize(at: url)

        if mode == .off {
            return ProcessResult(
                originalBytes: originalBytes,
                finalBytes: originalBytes,
                wasQuantized: false, wasOptimized: false,
                skipReason: "mode-off", analysis: nil
            )
        }

        let pngquantURL = SmartOutputLocator.pngquantURL()
        let oxipngURL = SmartOutputLocator.oxipngURL()
        if pngquantURL == nil || oxipngURL == nil {
            // .auto AND .adaptive degrade gracefully on missing binaries.
            // Power-user modes throw so the operator notices.
            if mode != .auto && mode != .adaptive {
                let missing = pngquantURL == nil ? "pngquant" : "oxipng"
                throw SmartOutputError.binaryMissing(missing)
            }
            return ProcessResult(
                originalBytes: originalBytes,
                finalBytes: originalBytes,
                wasQuantized: false, wasOptimized: false,
                skipReason: "no-binary", analysis: nil
            )
        }

        // Mode → pngquant decision + args.
        var pngquantArgs: [String]? = nil  // nil = skip pngquant (oxipng-only)
        var analysis: ContentDetector.Analysis? = nil
        var adaptivePicked: SmartOutputMode? = nil
        var fingerprint: ContentFingerprint? = nil

        switch mode {
        case .off:
            preconditionFailure("Unreachable — handled above")

        case .adaptive:
            // Single-pass content-aware picker. Compute rich fingerprint,
            // delegate to ContentClassifier, then continue with the picked
            // sub-mode's pngquant args.
            fingerprint = ContentClassifier.fingerprint(pngURL: url)
            let picked = fingerprint.map(ContentClassifier.pickAdaptiveMode) ?? .auto
            adaptivePicked = picked
            switch picked {
            case .auto:
                pngquantArgs = nil  // oxipng-only fallback
            case .softLoss:
                pngquantArgs = ["--speed", "1", "--quality", "40-90"]
            case .colors32:
                pngquantArgs = ["--speed", "1", "32"]
            case .colors8:
                pngquantArgs = ["--speed", "1", "8"]
            case .binarize:
                pngquantArgs = ["--speed", "1", "2"]
            case .off, .adaptive, .always:
                pngquantArgs = nil  // unreachable in picker output
            }

        case .auto:
            analysis = ContentDetector.analyze(pngURL: url)
            let lowEntropy = analysis?.isLowEntropy ?? false
            if lowEntropy {
                pngquantArgs = ["--speed", "1", "--quality", "65-100"]
            } else {
                pngquantArgs = nil
            }

        case .always:
            pngquantArgs = ["--speed", "1", "--quality", "65-100"]

        case .softLoss:
            pngquantArgs = ["--speed", "1", "--quality", "40-90"]

        case .colors32:
            pngquantArgs = ["--speed", "1", "32"]

        case .colors8:
            pngquantArgs = ["--speed", "1", "8"]

        case .binarize:
            pngquantArgs = ["--speed", "1", "2"]
        }

        // Stage tmp.
        let parent = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let tmpURL = parent.appendingPathComponent(".\(stem).smartout.\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        var wasQuantized = false
        if let qArgs = pngquantArgs {
            let exitCode = runPngquant(
                binary: pngquantURL!, input: url, output: tmpURL,
                extraArgs: qArgs
            )
            if exitCode == 0 {
                wasQuantized = true
            } else if exitCode == 99 {
                // pngquant gave up (quality too low or palette infeasible) —
                // fall back to copying original for oxipng to process.
                try copyFile(from: url, to: tmpURL)
            } else {
                throw SmartOutputError.quantizeFailed(stderr: "pngquant exit \(exitCode)")
            }
        } else {
            try copyFile(from: url, to: tmpURL)
        }

        let oxiExit = runOxipng(binary: oxipngURL!, target: tmpURL)
        if oxiExit != 0 {
            throw SmartOutputError.optimizeFailed(stderr: "oxipng exit \(oxiExit)")
        }

        let candidateBytes = fileSize(at: tmpURL)
        let ratio = originalBytes > 0 ? Double(candidateBytes) / Double(originalBytes) : 1.0

        if ratio > Self.sizeDeltaThreshold {
            return ProcessResult(
                originalBytes: originalBytes, finalBytes: originalBytes,
                wasQuantized: wasQuantized, wasOptimized: true,
                skipReason: "delta-guard", analysis: analysis,
                adaptivePicked: adaptivePicked, fingerprint: fingerprint
            )
        }

        try replace(at: url, with: tmpURL)
        return ProcessResult(
            originalBytes: originalBytes, finalBytes: candidateBytes,
            wasQuantized: wasQuantized, wasOptimized: true,
            skipReason: nil, analysis: analysis,
            adaptivePicked: adaptivePicked, fingerprint: fingerprint
        )
    }

    // MARK: - Subprocess helpers

    private func runPngquant(binary: URL, input: URL, output: URL, extraArgs: [String]) -> Int32 {
        let p = Process()
        p.executableURL = binary
        // Common args + variable mode-specific args.
        p.arguments = extraArgs + [
            "--output", output.path,
            "--force",
            input.path,
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

    private func runOxipng(binary: URL, target: URL) -> Int32 {
        let p = Process()
        p.executableURL = binary
        p.arguments = ["--opt", "2", target.path]
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
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private func copyFile(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        do {
            try fm.copyItem(at: src, to: dst)
        } catch {
            throw SmartOutputError.ioError("copy: \(error.localizedDescription)")
        }
    }

    private func replace(at dst: URL, with src: URL) throws {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            try fm.moveItem(at: src, to: dst)
        } catch {
            throw SmartOutputError.ioError("replace: \(error.localizedDescription)")
        }
    }
}
