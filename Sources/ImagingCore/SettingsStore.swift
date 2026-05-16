import Foundation
import Observation

// MARK: - SettingsStore

/// UserDefaults-backed settings, exposed as an `@Observable` model so that
/// SwiftUI views can two-way bind via `@Bindable`.
///
/// Defaults:
/// - enginePreference: "auto"   (Faz 2 — resolves to coreml on Apple Silicon)
/// - defaultModel:     "realesrgan-x4plus"
/// - defaultScale:     4
/// - defaultTileSize:  0   (auto)
/// - smartOutputMode:  .auto (post-upscale palette-aware compression)
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()

    public var enginePreference: String {
        didSet { UserDefaults.standard.set(enginePreference, forKey: Keys.enginePreference) }
    }

    public var defaultModel: String {
        didSet { UserDefaults.standard.set(defaultModel, forKey: Keys.defaultModel) }
    }

    public var defaultScale: Int {
        didSet { UserDefaults.standard.set(defaultScale, forKey: Keys.defaultScale) }
    }

    public var defaultTileSize: Int {
        didSet { UserDefaults.standard.set(defaultTileSize, forKey: Keys.defaultTileSize) }
    }

    public var smartOutputMode: SmartOutputMode {
        didSet { UserDefaults.standard.set(smartOutputMode.rawValue, forKey: Keys.smartOutputMode) }
    }

    /// Phase 3 (v0.3.3.0): opt-in automatic speckle/artifact cleanup for B/W
    /// line art outputs. Triggered after Smart Output content classification
    /// when `picked ∈ {.binarize, .colors8}` AND `fingerprint.nearBinaryScore
    /// >= 0.85`. See `DespeckleFilter` + `SmartOutputProcessor`.
    public var despeckleEnabled: Bool {
        didSet { UserDefaults.standard.set(despeckleEnabled, forKey: Keys.despeckleEnabled) }
    }

    /// Aggressiveness preset for `DespeckleFilter`. Stored as raw string
    /// (`@AppStorage` enum support is awkward); resolve via
    /// `DespecklePreset.from(rawValue:)`.
    public var despecklePreset: String {
        didSet { UserDefaults.standard.set(despecklePreset, forKey: Keys.despecklePreset) }
    }

    /// Phase 4 (v0.3.4.0 / refined v0.3.4.1): Line Art Enhance — luminance
    /// level mapping (median dropped in v0.3.4.1, empirically net-negative).
    /// Independent from despeckle; targets halo bastırma, not isolated dust.
    /// Default `false` (opt-in, customer enables when default still shows halo).
    public var lineArtEnhanceEnabled: Bool {
        didSet { UserDefaults.standard.set(lineArtEnhanceEnabled, forKey: Keys.lineArtEnhanceEnabled) }
    }

    /// Aggressiveness preset for `LineArtEnhanceFilter`. Stored as raw
    /// string; resolve via `LineArtEnhancePreset.from(rawValue:)`.
    public var lineArtEnhancePreset: String {
        didSet { UserDefaults.standard.set(lineArtEnhancePreset, forKey: Keys.lineArtEnhancePreset) }
    }

    private enum Keys {
        static let enginePreference = "engine.preference"
        static let defaultModel = "engine.defaultModel"
        static let defaultScale = "engine.defaultScale"
        static let defaultTileSize = "engine.defaultTileSize"
        static let smartOutputMode = "output.smartOutputMode"
        static let despeckleEnabled = "output.despeckleEnabled"
        static let despecklePreset = "output.despecklePreset"
        static let lineArtEnhanceEnabled = "output.lineArtEnhanceEnabled"
        static let lineArtEnhancePreset = "output.lineArtEnhancePreset"
    }

    /// Public initializer — primarily for `.shared`. A custom `UserDefaults`
    /// suite isn't supported here to keep the surface area small for Faz 1.
    public init() {
        let ud = UserDefaults.standard
        self.enginePreference = ud.string(forKey: Keys.enginePreference) ?? "auto"
        self.defaultModel = ud.string(forKey: Keys.defaultModel) ?? "realesrgan-x4plus"
        let scale = ud.integer(forKey: Keys.defaultScale)
        self.defaultScale = scale == 0 ? 4 : scale
        self.defaultTileSize = ud.integer(forKey: Keys.defaultTileSize) // 0 = auto, valid default
        self.smartOutputMode = SmartOutputMode(
            rawValue: ud.string(forKey: Keys.smartOutputMode) ?? ""
        ) ?? .adaptive
        // Despeckle defaults: enabled + normal preset (operator-canonical
        // aggressive default doctrine, consistent with Smart Output Adaptive).
        // ud.object(forKey:) check to differentiate "never set" from "false".
        if ud.object(forKey: Keys.despeckleEnabled) != nil {
            self.despeckleEnabled = ud.bool(forKey: Keys.despeckleEnabled)
        } else {
            self.despeckleEnabled = true
        }
        self.despecklePreset = ud.string(forKey: Keys.despecklePreset) ?? "normal"
        // Line Art Enhance: default OFF (opt-in).
        if ud.object(forKey: Keys.lineArtEnhanceEnabled) != nil {
            self.lineArtEnhanceEnabled = ud.bool(forKey: Keys.lineArtEnhanceEnabled)
        } else {
            self.lineArtEnhanceEnabled = false
        }
        self.lineArtEnhancePreset = ud.string(forKey: Keys.lineArtEnhancePreset) ?? "normal"
    }
}
