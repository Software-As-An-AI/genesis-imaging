import Foundation
import CoreML
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import StableDiffusion
import ImagingCore

/// Image generation engine — SDXL Base on Core ML, prompt-only Phase A.2.
///
/// Backed by Apple's `apple/ml-stable-diffusion` SwiftPM package and the
/// `apple/coreml-stable-diffusion-mixed-bit-palettization` model bundle
/// (palettized 6.71 GB, openrail++, pre-compiled `.mlmodelc` directories).
///
/// LoRA merge is NOT runtime-supported by `ml-stable-diffusion`. Coloring-
/// book LoRA conversion + merged-bundle ship is deferred to Phase A.3.
///
/// Critical SDXL configuration anchors (do not deviate without verifying):
///   - `encoderScaleFactor = 0.13025` (default 0.18215 is for SD 1.x — wrong
///     for SDXL; produces severely degraded output if left at default)
///   - `disableSafety = true` (SDXL has no built-in safety checker; saves
///     memory + avoids "all-black frame" surprise)
///   - `schedulerType = .dpmSolverMultistepScheduler` + Karras spacing
///     (community consensus for SDXL quality at 20-30 steps)
///   - `MLComputeUnits.cpuAndNeuralEngine` (Apple's recommendation for
///     palettized bundle; pipeline internally swaps VAE decoder to .cpuAndGPU
///     because ANE doesn't handle FP32)
///   - `reduceMemory: true` (M4 Pro 16 GB headroom for parallel Real-ESRGAN)
///
/// Output is fixed 1024×1024 per Apple's bundle geometry; UI may request
/// other sizes but the engine clamps to model's native resolution for v1.
/// Multi-size variants would require separate `.mlmodelc` bundles (defer A.3).
public struct StableDiffusionCoreMLEngine: GenerationEngine {
    public let engineName: String = "core-ml-sdxl"
    public let supportedModels: [String] = ["sdxl-line-art-lora"]

    /// Optional explicit bundle URL override (tests). When `nil`, the
    /// engine resolves `ModelDownloadManager.shared.bundleDirectory` lazily.
    private let modelBundleURLOverride: URL?

    public init(modelBundleURL: URL? = nil) {
        self.modelBundleURLOverride = modelBundleURL
    }

    public func probe() async throws -> EngineHealth {
        let installed = await MainActor.run { ModelDownloadManager.shared.isInstalled() }
        let version = await MainActor.run { ModelDownloadManager.shared.expectedVersion }
        return EngineHealth(
            isAvailable: installed,
            version: installed ? version : "model-not-installed",
            detectedDevice: installed ? "Apple Neural Engine" : nil
        )
    }

    public func generate(request: GenerationRequest) -> AsyncThrowingStream<GenerationProgress, Error> {
        let override = modelBundleURLOverride
        return AsyncThrowingStream { continuation in
            Task.detached {
                continuation.yield(.started)

                let installed = await MainActor.run {
                    ModelDownloadManager.shared.isInstalled()
                }
                guard installed else {
                    let err = GenerationError.modelNotInstalled
                    continuation.yield(.failed(err))
                    continuation.finish(throwing: err)
                    return
                }

                let bundleURL: URL
                if let override {
                    bundleURL = override
                } else {
                    bundleURL = await MainActor.run { ModelDownloadManager.shared.bundleDirectory }
                }

                do {
                    let result = try Self.runInference(
                        request: request,
                        bundleURL: bundleURL,
                        progressEmit: { step, total in
                            continuation.yield(.step(current: step, total: total))
                        }
                    )
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    let err = GenerationError.inferenceFailed("Cancelled")
                    continuation.yield(.failed(err))
                    continuation.finish(throwing: err)
                } catch let e as GenerationError {
                    continuation.yield(.failed(e))
                    continuation.finish(throwing: e)
                } catch {
                    let err = GenerationError.inferenceFailed(error.localizedDescription)
                    continuation.yield(.failed(err))
                    continuation.finish(throwing: err)
                }
            }
        }
    }

    // MARK: - Inference

    private static func runInference(
        request: GenerationRequest,
        bundleURL: URL,
        progressEmit: @escaping (Int, Int) -> Void
    ) throws -> GenerationResult {
        let startedAt = Date()

        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = .cpuAndNeuralEngine

        let pipeline: StableDiffusionXLPipeline
        do {
            pipeline = try StableDiffusionXLPipeline(
                resourcesAt: bundleURL,
                configuration: mlConfig,
                reduceMemory: true
            )
        } catch {
            throw GenerationError.modelLoadFailed("Pipeline init: \(error.localizedDescription)")
        }

        do {
            try pipeline.loadResources()
        } catch {
            throw GenerationError.modelLoadFailed("loadResources: \(error.localizedDescription)")
        }

        defer { pipeline.unloadResources() }

        var cfg = StableDiffusionPipeline.Configuration(prompt: request.prompt)
        cfg.negativePrompt = request.negativePrompt
        cfg.imageCount = 1
        cfg.stepCount = request.steps
        cfg.seed = request.seed
        cfg.guidanceScale = Float(request.cfgScale)
        cfg.schedulerType = .dpmSolverMultistepScheduler
        cfg.schedulerTimestepSpacing = .karras
        cfg.encoderScaleFactor = 0.13025
        cfg.decoderScaleFactor = 0.13025
        cfg.disableSafety = true
        cfg.useDenoisedIntermediates = false  // future: live preview
        cfg.originalSize = 1024
        cfg.targetSize = 1024

        let images: [CGImage?]
        do {
            images = try pipeline.generateImages(configuration: cfg) { progress in
                if Task.isCancelled { return false }
                // SDXL step is 0-indexed; UI labels 1..N
                progressEmit(progress.step + 1, progress.stepCount)
                return true
            }
        } catch {
            throw GenerationError.inferenceFailed(error.localizedDescription)
        }

        guard let first = images.first, let image = first else {
            throw GenerationError.inferenceFailed("Pipeline returned nil image (safety blocked or internal failure)")
        }

        let outputURL = try writePNG(cgImage: image, request: request)
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        return GenerationResult(
            outputURL: outputURL,
            seed: request.seed,
            durationMs: durationMs,
            engineName: "core-ml-sdxl"
        )
    }

    // MARK: - Output

    private static func writePNG(cgImage: CGImage, request: GenerationRequest) throws -> URL {
        let dir = try defaultOutputDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = generatedFileName(prompt: request.prompt, seed: request.seed)
        let url = dir.appendingPathComponent(fileName)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw GenerationError.ioError("CGImageDestination create failed: \(url.path)")
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw GenerationError.ioError("PNG finalize failed: \(url.path)")
        }
        return url
    }

    private static func defaultOutputDirectory() throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent("GenesisImaging", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
    }

    private static func generatedFileName(prompt: String, seed: UInt32) -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let slug = prompt
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "-")
        return "sdxl-\(stamp)-\(slug)-seed\(seed).png"
    }
}
