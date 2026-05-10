import Foundation
import ImagingCore
import NcnnEngine
import CoreMLEngine

/// Engine selection presented to the user. Persisted in Settings (Step 5b).
public enum EnginePreference: String, CaseIterable, Sendable {
    case ncnn
    case coreml
}

/// Single construction point for upscale engines. Keeps `MainView` and
/// `UpscaleViewModel` ignorant of concrete engine types — they always see
/// `any UpscaleEngine`. New engines plug in by extending the switch.
public enum EngineFactory {
    /// Construct an engine matching the preference. Throws on Phase 2 placeholder
    /// when CoreML chosen, or on missing binary when ncnn chosen.
    public static func makeEngine(preference: EnginePreference) throws -> any UpscaleEngine {
        switch preference {
        case .ncnn:   return try NcnnEngine()
        case .coreml: return try CoreMLEngine()
        }
    }
}
