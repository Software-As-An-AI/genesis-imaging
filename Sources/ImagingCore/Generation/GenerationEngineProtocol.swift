import Foundation

// MARK: - Request

/// Parameters for a single image-generation invocation. Mirrors
/// `UpscaleRequest` shape (Sendable + Equatable value type) so the
/// view-model + engine stay symmetric across the two pipelines.
public struct GenerationRequest: Sendable, Equatable {
    public let prompt: String
    public let negativePrompt: String
    public let seed: UInt32
    public let steps: Int
    public let cfgScale: Double
    public let width: Int
    public let height: Int
    public let modelName: String

    public init(
        prompt: String,
        negativePrompt: String = "",
        seed: UInt32,
        steps: Int = 30,
        cfgScale: Double = 7.5,
        width: Int = 1024,
        height: Int = 1024,
        modelName: String = GenerationDefaults.modelName
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.seed = seed
        self.steps = steps
        self.cfgScale = cfgScale
        self.width = width
        self.height = height
        self.modelName = modelName
    }
}

// MARK: - Result + progress

public struct GenerationResult: Sendable, Equatable {
    public let outputURL: URL
    public let seed: UInt32
    public let durationMs: Int
    public let engineName: String

    public init(outputURL: URL, seed: UInt32, durationMs: Int, engineName: String) {
        self.outputURL = outputURL
        self.seed = seed
        self.durationMs = durationMs
        self.engineName = engineName
    }
}

public enum GenerationProgress: Sendable {
    case started
    case step(current: Int, total: Int)
    case completed(GenerationResult)
    case failed(GenerationError)
}

public enum GenerationError: Error, Equatable {
    case modelNotInstalled
    case modelLoadFailed(String)
    case invalidPrompt(String)
    case inferenceFailed(String)
    case ioError(String)
}

// MARK: - Engine protocol

/// Image-generation engine contract. Mirrors `UpscaleEngine` — `probe()`
/// for capability discovery, stream-based generate() for progress + result.
public protocol GenerationEngine: Sendable {
    var engineName: String { get }
    var supportedModels: [String] { get }
    func probe() async throws -> EngineHealth
    func generate(request: GenerationRequest) -> AsyncThrowingStream<GenerationProgress, Error>
}

// MARK: - Defaults

/// Canonical defaults surfaced to UI + tests. Centralized so engine, view
/// model, and SettingsStore agree without copying constants.
public enum GenerationDefaults {
    public static let modelName: String = "sdxl-line-art-lora"
    public static let steps: Int = 30
    public static let cfgScale: Double = 7.5
    public static let width: Int = 1024
    public static let height: Int = 1024

    public static let supportedSizes: [(Int, Int)] = [
        (768, 768),
        (1024, 1024),
        (1024, 1536),
        (1536, 1024),
    ]

    /// Friendly short label for a (width, height) pair. Uses semantic terms
    /// (Kare / Dikey / Yatay) so the segmented picker can stay narrow and
    /// the customer doesn't decode aspect ratios from raw pixel counts.
    /// Falls back to verbatim `WxH` with no thousands separator (Turkish
    /// locale otherwise renders "1024" as "1.024" — confusing in a
    /// dimension context).
    public static func shortSizeLabel(width w: Int, height h: Int) -> String {
        switch (w, h) {
        case (768, 768):    return "Kare S"
        case (1024, 1024):  return "Kare M"
        case (1024, 1536):  return "Dikey"
        case (1536, 1024):  return "Yatay"
        default:            return String(format: "%d×%d", w, h)
        }
    }

    /// Verbatim `WxH` exposed as a stable token, useful for picker tags +
    /// Settings persistence (`SettingsStore.defaultGenerationSize`).
    public static func sizeTag(width w: Int, height h: Int) -> String {
        return "\(w)x\(h)"
    }

    /// Full descriptive label combining semantic + dimensions, suitable
    /// for Settings menu items where width allows the longer text.
    public static func longSizeLabel(width w: Int, height h: Int) -> String {
        let short = shortSizeLabel(width: w, height: h)
        return String(format: "%@ (%d×%d)", short, w, h)
    }
}
