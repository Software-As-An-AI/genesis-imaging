import Foundation
import ImagingCore
import NcnnEngine
import CoreMLEngine

/// Engine selection presented to the user. Persisted in Settings as a raw `String`.
public enum EnginePreference: String, CaseIterable, Sendable {
    /// Pick the best engine available on this device. On Apple Silicon (always
    /// the case for Genesis Imaging — `min_version: 14.0`, arch arm64), this
    /// resolves to `.coreml` because every supported device has an ANE.
    case auto
    case coreml
    case ncnn

    /// Decode a `SettingsStore.enginePreference` raw value, falling back to `.auto`.
    public static func from(rawValue raw: String) -> EnginePreference {
        EnginePreference(rawValue: raw) ?? .auto
    }

    /// User-facing display name (drives the Picker labels + footer text).
    public var displayName: String {
        switch self {
        case .auto:   return "Otomatik"
        case .coreml: return "Core ML"
        case .ncnn:   return "ncnn-vulkan"
        }
    }

    /// Resolve `.auto` to a concrete engine for the current device. Every
    /// supported Genesis Imaging host is Apple Silicon, so `.auto` always
    /// points to `.coreml`. The seam is here so a future Intel build (or
    /// CoreML init failure fallback) can re-route.
    public func resolveConcrete() -> EnginePreference {
        switch self {
        case .auto:
            #if arch(arm64)
            return .coreml
            #else
            return .ncnn
            #endif
        case .coreml, .ncnn:
            return self
        }
    }
}

/// Single construction point for upscale engines. Keeps `MainView` and
/// `UpscaleViewModel` ignorant of concrete engine types — they always see
/// `any UpscaleEngine`. New engines plug in by extending the switch.
public enum EngineFactory {
    /// Construct an engine matching the preference. For `.auto`, picks the
    /// device-best engine; if the preferred concrete engine fails to
    /// initialize, falls back to the alternative so the app stays usable.
    /// Explicit user picks (`.coreml`, `.ncnn`) DO NOT fall back — failures
    /// surface so the user can choose another option.
    public static func makeEngine(preference: EnginePreference) throws -> any UpscaleEngine {
        let resolved = preference.resolveConcrete()

        switch resolved {
        case .auto:
            // resolveConcrete never returns .auto — defensive
            return try NcnnEngine()
        case .coreml:
            do {
                return try CoreMLEngine()
            } catch where preference == .auto {
                // Auto path: if Core ML can't load (e.g., model missing on a
                // fresh checkout before fetch-coreml-model.sh has run), fall
                // back to ncnn so the app remains functional.
                return try NcnnEngine()
            }
        case .ncnn:
            return try NcnnEngine()
        }
    }
}
