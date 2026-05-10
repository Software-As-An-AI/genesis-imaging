import Foundation
import ImagingCore

/// Faz 1 implementation — wraps `realesrgan-ncnn-vulkan` binary as a subprocess.
/// Streams progress via `ProgressParser`. Cancellation propagates as SIGINT to the process.
public final class NcnnEngine: UpscaleEngine, @unchecked Sendable {
    public let engineName = "ncnn-vulkan"
    public let supportedModels = [
        "realesrgan-x4plus",
        "realesrgan-x4plus-anime",
        "realesr-animevideov3-x4",
        "realesr-animevideov3-x3",
        "realesr-animevideov3-x2",
    ]

    public func supportsScale(_ scale: Int) -> Bool {
        [2, 3, 4].contains(scale)
    }

    private let binaryURL: URL
    private let modelsDirectory: URL

    /// - Parameters:
    ///   - binaryURL: Override binary path. If `nil`, `BinaryLocator.defaultBinaryURL()` is used.
    ///   - modelsDirectory: Override models directory. If `nil`, `BinaryLocator.defaultModelsDirectory()` is used.
    public init(binaryURL: URL? = nil, modelsDirectory: URL? = nil) throws {
        self.binaryURL = try (binaryURL ?? BinaryLocator.defaultBinaryURL())
        try BinaryLocator.validate(binaryURL: self.binaryURL)
        self.modelsDirectory = try (modelsDirectory ?? BinaryLocator.defaultModelsDirectory())
    }

    public func upscale(request: UpscaleRequest) -> AsyncThrowingStream<UpscaleProgress, Error> {
        AsyncThrowingStream { continuation in
            // CRITICAL: AsyncThrowingStream's build closure runs synchronously on the
            // *consumer's* thread. If consumer is `@MainActor` (UI), running
            // `process.waitUntilExit()` here would freeze the window for the full
            // upscale duration. Hand the entire subprocess lifecycle to a background
            // queue; the continuation handle is Sendable and can be yielded into
            // from any thread.
            let binaryURL = self.binaryURL
            let modelsDirectory = self.modelsDirectory
            DispatchQueue.global(qos: .userInitiated).async {
                Self.runSubprocess(
                    request: request,
                    binaryURL: binaryURL,
                    modelsDirectory: modelsDirectory,
                    continuation: continuation
                )
            }
        }
    }

    /// All Process I/O lives on a background queue so SwiftUI's main thread stays free.
    private static func runSubprocess(
        request: UpscaleRequest,
        binaryURL: URL,
        modelsDirectory: URL,
        continuation: AsyncThrowingStream<UpscaleProgress, Error>.Continuation
    ) {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = buildArguments(request: request, modelsDirectory: modelsDirectory)

        let stderrPipe = Pipe()
        let stderrAccumulator = StderrAccumulator()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        let parser = ProgressParser { percent in
            continuation.yield(.percentage(percent))
        }

        // Stream stderr → parser as it arrives.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrAccumulator.append(data)
            if let chunk = String(data: data, encoding: .utf8) {
                parser.feed(chunk)
            }
        }

        // Cancellation: interrupt + (after grace) terminate.
        continuation.onTermination = { @Sendable _ in
            if process.isRunning {
                process.interrupt()  // SIGINT — graceful
                DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                    if process.isRunning { process.terminate() }  // SIGTERM
                }
            }
        }

        let startTime = Date()
        continuation.yield(.started)

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            continuation.finish(throwing: UpscaleError.ioError(message: "\(error)"))
            return
        }

        process.waitUntilExit()
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        parser.flush()

        let exitCode = process.terminationStatus
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // ncnn-vulkan v0.2.0 has unreliable exit codes — it returns 0 even when
        // the input file can't be decoded or the model isn't found. Validate
        // output existence + grep stderr for known failure markers.
        let stderrText = stderrAccumulator.utf8String
        let outputBytes = fileSize(at: request.outputURL)
        let stderrSuggestsFailure = stderrIndicatesFailure(stderrText)

        if exitCode == SIGINT || exitCode == SIGTERM {
            continuation.finish(throwing: UpscaleError.cancelled)
        } else if exitCode != 0 {
            continuation.finish(throwing: UpscaleError.engineFailure(
                exitCode: exitCode, stderr: stderrText
            ))
        } else if outputBytes == 0 || stderrSuggestsFailure {
            continuation.finish(throwing: UpscaleError.engineFailure(
                exitCode: 0,
                stderr: stderrText.isEmpty
                    ? "ncnn returned exit 0 but output file is empty/missing"
                    : stderrText
            ))
        } else {
            let inputBytes = fileSize(at: request.inputURL)
            let result = UpscaleResult(
                outputURL: request.outputURL,
                inputBytes: inputBytes,
                outputBytes: outputBytes,
                durationMs: durationMs,
                engineName: "ncnn-vulkan-v0.2.0"
            )
            continuation.yield(.completed(result))
            continuation.finish()
        }
    }

    public func probe() async throws -> EngineHealth {
        // The binary's only "info" path is its help output; running it confirms launchability.
        // Real Vulkan device detection requires running an actual upscale (header lines like
        // "[0 Apple M4 Pro]"); for probe we just confirm the binary is launchable.
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["-h"]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            // ncnn -h exits with non-zero (it treats help as an error path),
            // but that's fine — we only need to confirm the binary executed.
            return EngineHealth(
                isAvailable: true,
                version: "ncnn-vulkan-v0.2.0",
                detectedDevice: nil  // Resolved on first real upscale (parsed from stderr).
            )
        } catch {
            throw UpscaleError.binaryNotFound(path: binaryURL.path)
        }
    }

    // MARK: - Internals

    static func buildArguments(request: UpscaleRequest, modelsDirectory: URL) -> [String] {
        [
            "-i", request.inputURL.path,
            "-o", request.outputURL.path,
            "-n", request.modelName,
            "-s", "\(request.scale)",
            "-t", "\(request.tileSize)",
            "-m", modelsDirectory.path,
        ]
    }

    static func fileSize(at url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    /// ncnn writes "failed" / "error" to stderr on errors but still exits 0.
    /// We grep for known failure markers to detect this.
    static func stderrIndicatesFailure(_ stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("decode image") && lower.contains("failed")
            || lower.contains("encode image") && lower.contains("failed")
            || lower.contains("find_blob_index_by_name") && lower.contains("failed")
            || lower.contains("vkqueuesubmit failed")
            || lower.contains("model file not found")
    }
}

// MARK: - Stderr accumulator (thread-safe-ish — readabilityHandler invocations serialized)

private final class StderrAccumulator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ncnn-engine.stderr")
    private var data = Data()

    func append(_ chunk: Data) {
        queue.sync { self.data.append(chunk) }
    }

    var utf8String: String {
        queue.sync { String(data: data, encoding: .utf8) ?? "<binary>" }
    }
}
