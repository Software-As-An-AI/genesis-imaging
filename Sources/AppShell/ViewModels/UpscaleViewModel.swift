import Foundation
import Observation
import ImagingCore
import NcnnEngine

/// High-level upscale workflow state machine.
public enum UpscaleState: Sendable, Equatable {
    case idle
    case running
    case completed(URL)
    case failed(String)
}

/// Drives a single upscale pipeline: input selection → engine invocation →
/// progress streaming → terminal state. UI binds to its observable properties;
/// no engine type leaks through the surface.
@MainActor
@Observable
public final class UpscaleViewModel {
    // MARK: - Inputs (user-mutable)

    public var inputURL: URL?
    public var modelName: String = "realesrgan-x4plus"
    public var scale: Int = 4

    // MARK: - Outputs (read-mostly from UI)

    public var outputURL: URL?
    public var progress: Double = 0.0
    public var state: UpscaleState = .idle
    public var engineName: String = "ncnn-vulkan"

    // MARK: - Internals

    private var currentTask: Task<Void, Never>?

    public init() {}

    // MARK: - Public API

    /// User picked or dropped a new input — reset terminal state so a fresh
    /// run can start. Output URL is not derived until run begins.
    public func selectInput(_ url: URL) {
        cancel()
        inputURL = url
        outputURL = nil
        progress = 0.0
        state = .idle
    }

    /// Start the upscale pipeline. Safe to call only when `inputURL != nil`.
    /// No-op if a run is already in flight.
    public func startUpscale() async {
        guard let inputURL = inputURL else { return }
        // Don't re-enter while a run is active. After .completed / .failed,
        // allow a fresh start by resetting progress.
        if case .running = state { return }

        // Resolve output URL using the current Smart Output mode tag so the
        // filename advertises which compression pipeline produced it
        // (`<stem>-upscaled-<mode>.png`). Default Off keeps legacy filename.
        let smartMode = SettingsStore.shared.smartOutputMode
        let derivedOutput = Self.deriveOutputURL(for: inputURL, mode: smartMode)
        outputURL = derivedOutput
        state = .running
        progress = 0.0

        let request = UpscaleRequest(
            inputURL: inputURL,
            outputURL: derivedOutput,
            modelName: modelName,
            scale: scale
        )

        currentTask = Task { [weak self] in
            await self?.runStream(request: request)
        }
        await currentTask?.value
    }

    /// Cancel any in-flight upscale. Engine receives SIGINT via the
    /// `AsyncThrowingStream`'s `onTermination` hook.
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Stream consumer

    private func runStream(request: UpscaleRequest) async {
        let preference = EnginePreference.from(rawValue: SettingsStore.shared.enginePreference)
        let engine: any UpscaleEngine
        do {
            engine = try EngineFactory.makeEngine(preference: preference)
            engineName = engine.engineName
        } catch let UpscaleError.binaryNotFound(path) {
            state = .failed("Engine binary not found: \(path)")
            return
        } catch let UpscaleError.modelNotFound(name) {
            state = .failed("Engine model not found: \(name). Run scripts/fetch-coreml-model.sh.")
            return
        } catch {
            state = .failed("Engine init failed: \(error)")
            return
        }

        let stream = engine.upscale(request: request)
        do {
            for try await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .started:
                    progress = 0.0
                case .tile(let current, let total):
                    progress = total > 0 ? Double(current) / Double(total) : 0.0
                case .percentage(let pct):
                    progress = max(0.0, min(1.0, pct / 100.0))
                case .completed(let result):
                    progress = 1.0
                    // Strip quarantine xattr the engine subprocess inherited
                    // from the sandboxed parent — blocks web upload pipelines
                    // (Canva, Drive) otherwise. See QuarantineUtil.
                    QuarantineUtil.stripQuarantine(at: result.outputURL)
                    // Post-process: palette-aware compression. Engine succeeded —
                    // any failure here is non-fatal (engine's output is on disk).
                    let smartMode = SettingsStore.shared.smartOutputMode
                    var finalOutputURL = result.outputURL
                    if smartMode != .off {
                        do {
                            let pr = try SmartOutputProcessor().process(
                                url: result.outputURL, mode: smartMode
                            )
                            // When .adaptive picked a concrete sub-mode, rewrite
                            // the filename to advertise it: `-upscaled-adaptive`
                            // → `-upscaled-adaptive-<picked>`.
                            if smartMode == .adaptive, let picked = pr.adaptivePicked {
                                if let renamed = Self.renameWithAdaptivePicked(
                                    url: result.outputURL, picked: picked
                                ) {
                                    finalOutputURL = renamed
                                }
                            }
                        } catch {
                            FileHandle.standardError.write(Data(
                                "[smart-output] post-process failed (non-fatal): \(error)\n".utf8
                            ))
                        }
                    }
                    outputURL = finalOutputURL
                    state = .completed(finalOutputURL)
                    await Self.notifyCompleted(result: result, request: request)
                case .failed(let err):
                    state = .failed(Self.describe(err))
                    await Notifier.shared.errorChime()
                }
            }
            // Stream ended without explicit completion event but no error —
            // treat as success only if we already saw .completed.
            if case .running = state {
                state = .failed("Engine stream ended without completion event")
            }
        } catch is CancellationError {
            state = .failed("Cancelled")
        } catch let error as UpscaleError {
            state = .failed(Self.describe(error))
            await Notifier.shared.errorChime()
        } catch {
            state = .failed("\(error)")
            await Notifier.shared.errorChime()
        }
    }

    private static func notifyCompleted(result: UpscaleResult, request: UpscaleRequest) async {
        let inputName = request.inputURL.lastPathComponent
        let durationSec = Double(result.durationMs) / 1000.0
        let body = String(format: "%@ → %d× upscaled in %.1f s",
                          inputName, request.scale, durationSec)
        await Notifier.shared.notify(title: "Genesis Imaging", body: body)
    }

    // MARK: - Helpers

    /// Compute `<input-stem>-upscaled[-<mode-tag>].png` next to the input file.
    /// `.off` mode keeps the legacy `<stem>-upscaled.png` filename for
    /// backward compat. All other modes append the mode tag so the operator
    /// can tell at a glance which compression pipeline produced the file.
    /// Resolves collisions by appending `-1`, `-2`, ... before the extension.
    static func deriveOutputURL(for input: URL, mode: SmartOutputMode = .auto) -> URL {
        let dir = input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let tagSuffix = mode.filenameTag.map { "-\($0)" } ?? ""
        let base = "\(stem)-upscaled\(tagSuffix)"

        let candidate = dir.appendingPathComponent("\(base).png")
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        var counter = 1
        while true {
            let next = dir.appendingPathComponent("\(base)-\(counter).png")
            if !FileManager.default.fileExists(atPath: next.path) {
                return next
            }
            counter += 1
        }
    }

    /// Rename a file that ends in `-upscaled-adaptive.png` (or `-adaptive-<n>.png`)
    /// to inject the picked sub-mode tag: `-upscaled-adaptive-<picked>.png`.
    /// Returns the new URL on success, or `nil` if rename failed.
    static func renameWithAdaptivePicked(url: URL, picked: SmartOutputMode) -> URL? {
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let pickedTag = picked.filenameTag ?? "lossless"
        // Replace trailing `-adaptive` (with optional collision suffix) with
        // `-adaptive-<picked>`.
        // Examples:
        //   foo-upscaled-adaptive          → foo-upscaled-adaptive-binarize
        //   foo-upscaled-adaptive-1        → foo-upscaled-adaptive-binarize-1
        //   foo-upscaled-x4-adaptive       → foo-upscaled-x4-adaptive-binarize
        var newStem = stem
        if let range = newStem.range(of: "-adaptive") {
            let after = newStem[range.upperBound...]  // suffix after -adaptive
            newStem = String(newStem[..<range.upperBound]) + "-\(pickedTag)" + String(after)
        } else {
            // Defensive — current filename doesn't carry the adaptive tag.
            // Just append the picked tag so we still convey traceability.
            newStem = "\(stem)-\(pickedTag)"
        }

        let newURL = dir.appendingPathComponent(newStem).appendingPathExtension(ext)
        if newURL == url { return url }

        do {
            // If a file already exists at the target (rare), let the rename fail
            // gracefully and surface the original URL — the bytes are still there.
            if FileManager.default.fileExists(atPath: newURL.path) {
                return nil
            }
            try FileManager.default.moveItem(at: url, to: newURL)
            QuarantineUtil.stripQuarantine(at: newURL)
            return newURL
        } catch {
            return nil
        }
    }

    static func describe(_ error: UpscaleError) -> String {
        switch error {
        case .binaryNotFound(let path):
            return "Engine binary not found: \(path)"
        case .modelNotFound(let name):
            return "Model not found: \(name)"
        case .unsupportedFormat(let mediaType):
            return "Unsupported format: \(mediaType)"
        case .engineFailure(let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = trimmed.count > 240 ? String(trimmed.prefix(240)) + "…" : trimmed
            return "Engine failed (exit \(exitCode)): \(snippet)"
        case .cancelled:
            return "Cancelled"
        case .ioError(let message):
            return "I/O error: \(message)"
        case .notImplemented(let reason):
            return "Not implemented: \(reason)"
        }
    }
}
