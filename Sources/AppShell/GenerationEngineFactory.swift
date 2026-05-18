import Foundation
import ImagingCore
import CoreMLEngine

/// Construction point for image-generation engines, dispatching on
/// `SDXLModelCatalog.Variant.engineKind`. Mirrors the upscale-side
/// `EngineFactory` pattern (`Sources/AppShell/EngineFactory.swift`) so view
/// models stay engine-agnostic — they ask for the engine that matches the
/// currently-selected variant and the factory hands one back.
///
/// Phase A.4 introduced the second `engineKind` (`.mlxFlux`) on top of the
/// pre-existing Core ML SDXL pipeline. New engine kinds plug in by adding a
/// case to the switch in `engine(for:)`.
public enum GenerationEngineFactory {
    /// Return a fresh engine matching the variant's `engineKind`. The factory
    /// does NOT cache instances — engines are cheap structs/classes whose
    /// real state lives in the Core ML / MLX runtime, which has its own
    /// caching layer.
    public static func engine(for variant: SDXLModelCatalog.Variant) -> any GenerationEngine {
        switch variant.engineKind {
        case .coreMLSDXL:
            return StableDiffusionCoreMLEngine()
        case .mlxFlux:
            return Flux2KleinEngine()
        }
    }

    /// Convenience: engine for the currently-selected variant in Settings.
    /// `GenerationViewModel.start()` uses this so it doesn't need to know
    /// about the catalog directly.
    @MainActor
    public static func engineForCurrentVariant() -> any GenerationEngine {
        engine(for: SettingsStore.shared.sdxlModelVariantTyped)
    }
}
