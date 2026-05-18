import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ImagingCore
import Flux2Core

/// FLUX.2 Klein 4B image-generation engine, native Swift MLX runtime.
///
/// Wraps `flux-2-swift-mlx`'s `Flux2Pipeline` behind our `GenerationEngine`
/// protocol. Inference defaults match the operator-locked Phase A.4 plan
/// §Step 6 — Klein 4B at the package's `.balanced` quantization preset
/// (transformer int4 + text encoder 4-bit), 4 steps, guidance 1.0, 1024²
/// resolution.
///
/// Spike-proven (2026-05-18): 35-45 sec/image on M4 Pro, dramatically
/// tighter minimalist coloring-book aesthetic than SDXL+LoRA.
///
/// Path resolution: `Flux2Core.ModelRegistry.customModelsDirectory` is
/// reset on every `generate()` to our `bundleDirectory(for: .fluxKlein)`
/// so the library's auto-discovery hits the files our multi-file
/// downloader placed (Step 3). Qwen3 text encoder is auto-downloaded by
/// the library at first generation into the same directory.
///
/// Metallib distribution: the runtime MLX library needs `mlx.metallib`
/// reachable via either an MLX-Swift framework bundle or a symlink/copy
/// alongside the executable. Step 5 (metallib bundling) handles
/// production app shipment; for `swift run` development the
/// `setup-lora-env.sh` symlink at `tools/flux-spike/mlx.metallib` is
/// reused — fine for spike + tests, replaced with proper app-bundle
/// bundling in Step 5.
public struct Flux2KleinEngine: GenerationEngine {
    public let engineName: String = "mlx-flux-klein-4b"
    public let supportedModels: [String] = ["flux-2-klein-4b-balanced"]

    public init() {}

    public func probe() async throws -> EngineHealth {
        let installed = await MainActor.run {
            ModelDownloadManager.shared.isInstalled(for: .fluxKlein)
        }
        return EngineHealth(
            isAvailable: installed,
            version: SDXLModelCatalog.Variant.fluxKlein.versionMarker,
            detectedDevice: installed ? "Apple Silicon (MLX)" : nil
        )
    }

    public func generate(request: GenerationRequest) -> AsyncThrowingStream<GenerationProgress, Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                continuation.yield(.started)

                // Pre-flight: bundle present?
                let installed = await MainActor.run {
                    ModelDownloadManager.shared.isInstalled(for: .fluxKlein)
                }
                guard installed else {
                    let err = GenerationError.modelNotInstalled
                    continuation.yield(.failed(err))
                    continuation.finish(throwing: err)
                    return
                }

                // Redirect flux-2-swift-mlx model search to our bundle dir.
                // Sets every time in case other variants change the global.
                let bundleDir = await MainActor.run {
                    ModelDownloadManager.shared.bundleDirectory(for: .fluxKlein)
                }
                ModelRegistry.customModelsDirectory = bundleDir

                // Build pipeline with operator-locked defaults.
                let pipeline = Flux2Pipeline(
                    model: .klein4B,
                    quantization: .balanced
                )

                // Load models (Qwen3 auto-downloads here on first run, ~3 GB).
                do {
                    try await pipeline.loadModels(progressCallback: nil)
                } catch {
                    let err = GenerationError.modelLoadFailed(
                        "Flux2Pipeline loadModels: \(error.localizedDescription)"
                    )
                    continuation.yield(.failed(err))
                    continuation.finish(throwing: err)
                    return
                }

                // Honest mapping: Klein at guidance 1.0 ignores negative
                // prompts (no classifier-free guidance). We still record the
                // user's negative input via request but don't pass it on —
                // Klein's pipeline does not accept one.
                let steps = max(1, request.steps)
                let guidance = Float(request.cfgScale)
                let seed = UInt64(request.seed)

                // Stream per-step progress.
                let progressCallback: Flux2ProgressCallback = { step, total in
                    continuation.yield(.step(current: step + 1, total: total))
                }

                let started = Date()
                do {
                    let image = try await pipeline.generateTextToImage(
                        prompt: request.prompt,
                        height: request.height,
                        width: request.width,
                        steps: steps,
                        guidance: guidance,
                        seed: seed,
                        upsamplePrompt: false,
                        onProgress: progressCallback
                    )
                    let outputURL = try Self.writePNG(image: image, request: request)
                    let durationMs = Int(Date().timeIntervalSince(started) * 1000)
                    let result = GenerationResult(
                        outputURL: outputURL,
                        seed: request.seed,
                        durationMs: durationMs,
                        engineName: "mlx-flux-klein-4b"
                    )
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    let err = GenerationError.inferenceFailed("Cancelled")
                    continuation.yield(.failed(err))
                    continuation.finish(throwing: err)
                } catch {
                    let err = GenerationError.inferenceFailed(error.localizedDescription)
                    continuation.yield(.failed(err))
                    continuation.finish(throwing: err)
                }
            }
        }
    }

    // MARK: - Output

    private static func writePNG(image: CGImage, request: GenerationRequest) throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("GenesisImaging", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let slug = request.prompt
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "-")
        let fileName = "flux-\(stamp)-\(slug)-seed\(request.seed).png"
        let url = dir.appendingPathComponent(fileName)

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1, nil
        ) else {
            throw GenerationError.ioError("CGImageDestination create failed: \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw GenerationError.ioError("PNG finalize failed: \(url.path)")
        }
        return url
    }
}
