import Foundation
import ImagingCore

/// Faz 2 placeholder. `init` throws `.notImplemented` — UI/EngineFactory
/// can construct it for type-checking but not invoke it. When Faz 2 starts,
/// only the body of `init` and `upscale` change; protocol conformance
/// (and therefore all callers) stays identical.
public final class CoreMLEngine: UpscaleEngine {
    public let engineName = "coreml"
    public let supportedModels: [String] = ["realesrgan-x4plus"]

    public func supportsScale(_ scale: Int) -> Bool { scale == 4 }

    public init() throws {
        throw UpscaleError.notImplemented(
            reason: "Core ML engine is planned for Phase 2. " +
                    "Track plan: docs/plans/enumerated-herding-scroll.md §8"
        )
    }

    public func upscale(request: UpscaleRequest) -> AsyncThrowingStream<UpscaleProgress, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(
                throwing: UpscaleError.notImplemented(reason: "Phase 2 — see plan §8")
            )
        }
    }

    public func probe() async throws -> EngineHealth {
        EngineHealth(isAvailable: false, version: "phase-2-pending", detectedDevice: nil)
    }
}
