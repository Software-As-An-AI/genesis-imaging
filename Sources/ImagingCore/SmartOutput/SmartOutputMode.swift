import Foundation

/// Operating mode for `SmartOutputProcessor`. 7 discrete modes spanning the
/// quality-vs-size trade-off space, calibrated against real coloring-book
/// content (2026-05-13 empirical pass on 4 customer files).
///
/// Approximate output sizes for a typical 1254×1254 B/W coloring book input
/// (~2.2 MB) upscaled 4× to 5016×5016:
///
/// | Mode         | Output       | Quality loss            |
/// |--------------|--------------|-------------------------|
/// | `.off`       | 20-25 MB     | None (engine raw)       |
/// | `.auto`      | 7-9 MB       | None (near-lossless)    |
/// | `.always`    | 7-9 MB       | None (near-lossless)    |
/// | `.softLoss`  | ~4 MB        | Minimal                 |
/// | `.colors32`  | ~4 MB        | Slight palette banding  |
/// | `.colors8`   | ~2 MB        | Visible posterization   |
/// | `.binarize`  | ~0.5 MB      | Jagged edges (no AA)    |
public enum SmartOutputMode: String, Sendable, CaseIterable, Equatable {
    case off
    case adaptive                  // content-aware picker (Phase 2 default)
    case auto
    case always
    case softLoss    = "soft"      // pngquant --quality 40-90
    case colors32    = "32color"   // pngquant 32 max colors
    case colors8     = "lineart"   // pngquant 8 max colors
    case binarize    = "binarize"  // pngquant 2 max colors (pure B/W)

    public var label: String {
        switch self {
        case .off:       return "Kapalı (ham)"
        case .adaptive:  return "Smart Auto (Akıllı Otomatik)"
        case .auto:      return "Yüksek Kalite (Lossless)"
        case .always:    return "Her Zaman Sıkıştır"
        case .softLoss:  return "Yumuşak Kayıp"
        case .colors32:  return "32 Renk Paleti"
        case .colors8:   return "Line Art (8 Renk)"
        case .binarize:  return "Saf B/W (2 Renk)"
        }
    }

    /// Short tag injected into output filename for traceability.
    /// Result: `<stem>-upscaled-<tag>.png`. Off mode keeps the legacy
    /// `<stem>-upscaled.png` filename to preserve backward compat.
    /// Adaptive mode's tag is computed at runtime by composing with the
    /// picked sub-mode (e.g. `adaptive-binarize`); see `adaptiveTagComposing(picked:)`.
    public var filenameTag: String? {
        switch self {
        case .off:       return nil  // legacy: no suffix
        case .adaptive:  return "adaptive"
        case .auto:      return "auto"
        case .always:    return "always"
        case .softLoss:  return "soft"
        case .colors32:  return "32color"
        case .colors8:   return "lineart"
        case .binarize:  return "binarize"
        }
    }

    /// Compose the adaptive filename tag with the sub-mode that was picked.
    /// Returns e.g. `"adaptive-binarize"` or `"adaptive-lineart"`. Only valid
    /// when `self == .adaptive`. Falls back to `.adaptive` tag for non-adaptive callers.
    public static func adaptiveTagComposing(picked: SmartOutputMode) -> String {
        let pickedTag = picked.filenameTag ?? "lossless"
        return "adaptive-\(pickedTag)"
    }

    public var hint: String {
        switch self {
        case .off:
            return "Motor ham çıktısı (~20-25 MB B/W için). Sıkıştırma yok."
        case .adaptive:
            return "İçerik-bilinçli aggressive seçim — B/W için 0.5-2 MB, fotoğraf için lossless. Dosya adına seçilen yöntem yazılır."
        case .auto:
            return "İçerik-bilinçli near-lossless: B/W ve sınırlı palet quantize edilir; fotoğraf lossless korunur. ~7-9 MB B/W için."
        case .always:
            return "Her zaman pngquant + oxipng. ~7-9 MB B/W için. Fotoğraf hafif palet bandı görebilir."
        case .softLoss:
            return "Quality 40-90 — minimal görsel kayıp, ~4 MB. Email upload için."
        case .colors32:
            return "32 renk paleti — cartoon/coloring book friendly, ~4 MB. Hafif palet bandı."
        case .colors8:
            return "8 renk paleti — line art için, ~2 MB. Görünür posterization."
        case .binarize:
            return "Saf siyah-beyaz (2 renk) — anti-aliasing yok, jagged edges, ~0.5 MB. Maksimum sıkıştırma."
        }
    }
}
