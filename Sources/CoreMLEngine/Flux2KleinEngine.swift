import Foundation
import ImagingCore

/// FLUX.2 Klein 4B image-generation engine, native Swift MLX runtime.
///
/// **Step 2 stub** — surface only. Conforms to `GenerationEngine` so the
/// engine factory can return it for `.fluxKlein` variants, but `generate()`
/// currently throws `GenerationError.modelNotInstalled` since the flux-2-
/// swift-mlx library integration hasn't landed yet.
///
/// Step 4 (~1.5 days) wires this up:
///   1. Import `Flux2Core` + `FluxTextEncoders` products from
///      `flux-2-swift-mlx` package (already on Package.swift since Step 0)
///   2. Map `GenerationRequest` → `Flux2GenerationConfiguration`
///   3. Stream per-step progress through `AsyncThrowingStream`
///   4. Bundle path resolution from
///      `ModelDownloadManager.resourcesDirectory(for: .fluxKlein)`
///   5. Move file to dedicated `Sources/FluxEngine/` target if isolation
///      becomes valuable
///
/// Inference defaults (operator-locked, see Phase A.4 plan §Step 6):
///   - transformer quant: int4 (4 GB bundle, ~16 GB peak RAM)
///   - text-encoder quant: 4-bit (Qwen3-4B-MLX-4bit)
///   - steps: 4 (Klein default; faster than SDXL's 30)
///   - guidance: 1.0 (Klein default; no classifier-free guidance)
///   - resolution: 1024×1024
///
/// Spike-proven: 35-45 sec per image on M4 Pro, dramatically better
/// minimalist coloring-book aesthetic than SDXL+LoRA (Phase A.3 ship).
public struct Flux2KleinEngine: GenerationEngine {
    public let engineName: String = "mlx-flux-klein-4b"
    public let supportedModels: [String] = ["flux-2-klein-4b-int4-qwen3-4b-4bit"]

    public init() {}

    public func probe() async throws -> EngineHealth {
        EngineHealth(
            isAvailable: false,
            version: "step-2-stub",
            detectedDevice: nil
        )
    }

    public func generate(request: GenerationRequest) -> AsyncThrowingStream<GenerationProgress, Error> {
        AsyncThrowingStream { continuation in
            let err = GenerationError.modelNotInstalled
            continuation.yield(.failed(err))
            continuation.finish(throwing: err)
        }
    }
}
