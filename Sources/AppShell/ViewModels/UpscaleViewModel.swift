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

        let derivedOutput = Self.deriveOutputURL(for: inputURL)
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
                    state = .completed(result.outputURL)
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

    /// Compute `<input-stem>-upscaled.png` next to the input file.
    /// Resolves collisions by appending `-1`, `-2`, ... before the suffix.
    static func deriveOutputURL(for input: URL) -> URL {
        let dir = input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent
        let candidate = dir.appendingPathComponent("\(stem)-upscaled.png")
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        var counter = 1
        while true {
            let next = dir.appendingPathComponent("\(stem)-upscaled-\(counter).png")
            if !FileManager.default.fileExists(atPath: next.path) {
                return next
            }
            counter += 1
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
