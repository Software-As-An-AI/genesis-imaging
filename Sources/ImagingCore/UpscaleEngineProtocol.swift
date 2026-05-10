import Foundation

// MARK: - Public Protocol

/// Engine-agnostic contract for any upscale implementation.
/// Faz 1: NcnnEngine (subprocess). Faz 2: CoreMLEngine (Apple Neural Engine).
/// UI is written against this protocol — engine swap = zero UI change.
public protocol UpscaleEngine: Sendable {
    var engineName: String { get }
    var supportedModels: [String] { get }

    /// Returns true if the engine supports the given integer scale factor (e.g. 2, 3, 4).
    func supportsScale(_ scale: Int) -> Bool

    /// Streams progress events; finishes with `.completed` or throws `UpscaleError`.
    func upscale(request: UpscaleRequest) -> AsyncThrowingStream<UpscaleProgress, Error>

    /// Health check — used by UI footer ("Engine: ncnn-vulkan v0.2.0, Device: Apple M4").
    func probe() async throws -> EngineHealth
}

// MARK: - Request / Result

public struct UpscaleRequest: Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let modelName: String
    public let scale: Int
    public let tileSize: Int
    public let outputFormat: OutputFormat

    public init(inputURL: URL, outputURL: URL, modelName: String, scale: Int,
                tileSize: Int = 0, outputFormat: OutputFormat = .png) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.modelName = modelName
        self.scale = scale
        self.tileSize = tileSize
        self.outputFormat = outputFormat
    }
}

public enum OutputFormat: Sendable, Equatable {
    case png
    case jpeg(quality: Double)
    case webp
}

public struct UpscaleResult: Sendable {
    public let outputURL: URL
    public let inputBytes: Int
    public let outputBytes: Int
    public let durationMs: Int
    public let engineName: String
    public let warnings: [String]

    public init(outputURL: URL, inputBytes: Int, outputBytes: Int,
                durationMs: Int, engineName: String, warnings: [String] = []) {
        self.outputURL = outputURL
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
        self.durationMs = durationMs
        self.engineName = engineName
        self.warnings = warnings
    }
}

// MARK: - Progress

public enum UpscaleProgress: Sendable {
    case started
    case tile(current: Int, total: Int)
    case percentage(Double)
    case completed(UpscaleResult)
    case failed(UpscaleError)
}

// MARK: - Errors

public enum UpscaleError: Error, Sendable, Equatable {
    case binaryNotFound(path: String)
    case modelNotFound(name: String)
    case unsupportedFormat(mediaType: String)
    case engineFailure(exitCode: Int32, stderr: String)
    case cancelled
    case ioError(message: String)
    case notImplemented(reason: String)
}

// MARK: - Health

public struct EngineHealth: Sendable {
    public let isAvailable: Bool
    public let version: String
    public let detectedDevice: String?

    public init(isAvailable: Bool, version: String, detectedDevice: String? = nil) {
        self.isAvailable = isAvailable
        self.version = version
        self.detectedDevice = detectedDevice
    }
}
