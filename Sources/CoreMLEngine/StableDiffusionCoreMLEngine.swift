import Foundation
import CoreML
import ImagingCore

/// Image generation engine — SDXL Base + Line-Art LoRA merged via Apple
/// Core ML, running primarily on Apple Neural Engine.
///
/// v0.4.0.0 ships the scaffold: protocol conformance + model presence
/// check + clear `.modelNotInstalled` failure when the bundle is missing.
/// Full inference pipeline (text encoder → UNet loop → VAE decode) lands
/// in v0.4.0.1 after the model conversion + SwiftPM dependency wire-up.
///
/// Pattern reuse from `CoreMLEngine.swift` (Real-ESRGAN, Faz 2):
///   - `MLModelConfiguration(.all)` ANE preference
///   - `ComputePlanInspector` ANE delegation verification
///   - Stream-based progress reporting (`AsyncThrowingStream`)
///
/// Hugging Face port reference: `apple/coreml-stable-diffusion-xl-base`
/// (Apple official) + community line-art LoRA merged at conversion time.
public struct StableDiffusionCoreMLEngine: GenerationEngine {
    public let engineName: String = "core-ml-sdxl"
    public let supportedModels: [String] = ["sdxl-line-art-lora"]

    /// Optional explicit bundle URL override (tests). When `nil`, the
    /// engine resolves the manager's default at use-time inside async
    /// actor-isolated contexts.
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
        AsyncThrowingStream { continuation in
            Task.detached {
                continuation.yield(.started)

                // v0.4.0.0 scaffold: model not yet wired. Fail fast with a
                // clear actionable message so the UI surfaces the right
                // download CTA instead of pretending to run.
                let installed = await MainActor.run {
                    ModelDownloadManager.shared.isInstalled()
                }
                guard installed else {
                    let err = GenerationError.modelNotInstalled
                    continuation.yield(.failed(err))
                    continuation.finish(throwing: err)
                    return
                }

                // TODO (v0.4.0.1): wire Apple ml-stable-diffusion Swift
                // package — load TextEncoder, run UNet step loop yielding
                // .step(current, total) per iteration, decode via VAE, write
                // PNG via shared encoder + emit .completed(result).
                let err = GenerationError.inferenceFailed(
                    "v0.4.0.0 scaffold — inference pipeline lands in v0.4.0.1"
                )
                continuation.yield(.failed(err))
                continuation.finish(throwing: err)
            }
        }
    }
}
