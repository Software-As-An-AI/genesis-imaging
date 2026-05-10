import Foundation
import Observation

// MARK: - SettingsStore

/// UserDefaults-backed settings, exposed as an `@Observable` model so that
/// SwiftUI views can two-way bind via `@Bindable`.
///
/// Defaults:
/// - enginePreference: "ncnn"
/// - defaultModel:     "realesrgan-x4plus"
/// - defaultScale:     4
/// - defaultTileSize:  0   (auto)
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

    private enum Keys {
        static let enginePreference = "engine.preference"
        static let defaultModel = "engine.defaultModel"
        static let defaultScale = "engine.defaultScale"
        static let defaultTileSize = "engine.defaultTileSize"
    }

    /// Public initializer — primarily for `.shared`. A custom `UserDefaults`
    /// suite isn't supported here to keep the surface area small for Faz 1.
    public init() {
        let ud = UserDefaults.standard
        self.enginePreference = ud.string(forKey: Keys.enginePreference) ?? "ncnn"
        self.defaultModel = ud.string(forKey: Keys.defaultModel) ?? "realesrgan-x4plus"
        let scale = ud.integer(forKey: Keys.defaultScale)
        self.defaultScale = scale == 0 ? 4 : scale
        self.defaultTileSize = ud.integer(forKey: Keys.defaultTileSize) // 0 = auto, valid default
    }
}
