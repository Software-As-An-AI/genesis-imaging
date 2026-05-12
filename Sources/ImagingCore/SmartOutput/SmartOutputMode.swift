import Foundation

/// Operating mode for `SmartOutputProcessor`.
///
/// - `.off` — Skip post-processing entirely. Output is whatever the engine wrote.
/// - `.auto` — Detect content type. Quantize if low-entropy (line art / B/W /
///   limited palette), otherwise oxipng-only (lossless deflate optimizer).
/// - `.always` — Force pngquant + oxipng regardless of content. Power users.
///
/// Default is `.auto`. Persisted in `SettingsStore.smartOutputMode`.
public enum SmartOutputMode: String, Sendable, CaseIterable, Equatable {
    case off
    case auto
    case always

    public var label: String {
        switch self {
        case .off:    return "Kapalı"
        case .auto:   return "Otomatik"
        case .always: return "Her Zaman"
        }
    }
}
