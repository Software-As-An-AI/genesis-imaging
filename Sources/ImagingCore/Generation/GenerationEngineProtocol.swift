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
}
