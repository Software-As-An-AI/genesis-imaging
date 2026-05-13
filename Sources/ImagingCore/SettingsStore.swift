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

    private enum Keys {
        static let enginePreference = "engine.preference"
        static let defaultModel = "engine.defaultModel"
        static let defaultScale = "engine.defaultScale"
        static let defaultTileSize = "engine.defaultTileSize"
        static let smartOutputMode = "output.smartOutputMode"
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
    }
}
