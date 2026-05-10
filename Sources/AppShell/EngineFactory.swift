import Foundation
import ImagingCore
import NcnnEngine
import CoreMLEngine

/// Engine selection presented to the user. Persisted in Settings as a raw `String`.
public enum EnginePreference: String, CaseIterable, Sendable {
    case ncnn
    case coreml

    /// Decode a `SettingsStore.enginePreference` raw value, falling back to `.ncnn`.
    public static func from(rawValue raw: String) -> EnginePreference {
        EnginePreference(rawValue: raw) ?? .ncnn
    }

    /// User-facing display name (drives the Picker labels + footer text).
    public var displayName: String {
        switch self {
        case .ncnn:   return "ncnn-vulkan"
        case .coreml: return "Core ML"
        }
    }
}

/// Single construction point for upscale engines. Keeps `MainView` and
/// `UpscaleViewModel` ignorant of concrete engine types — they always see
/// `any UpscaleEngine`. New engines plug in by extending the switch.
public enum EngineFactory {
    /// Construct an engine matching the preference.
    public static func makeEngine(preference: EnginePreference) throws -> any UpscaleEngine {
        switch preference {
        case .ncnn:   return try NcnnEngine()
        case .coreml: return try CoreMLEngine()
        }
    }
}
