import Foundation
import ImagingCore

/// Locates a Core ML model file on disk. Same lookup strategy as `BinaryLocator`
/// for the ncnn binary — production app bundle first, then repo dev layout.
///
///   1. App bundle: `<MainBundle>/Contents/Resources/models/<modelName>.mlmodel`
///   2. Repo dev: `<CWD>/Resources/models/<modelName>.mlmodel`
public enum ModelLocator {
    /// Default Faz 2 model filename (without extension).
    public static let defaultModelName = "RealESRGAN_x4plus"

    /// File extension the locator looks up. Core ML's runtime API loads
    /// `.mlmodelc` (compiled, optimized) — not the source `.mlmodel` spec.
    /// `scripts/fetch-coreml-model.sh` downloads the source and invokes
    /// `xcrun coremlcompiler compile` to produce the `.mlmodelc` directory bundle.
    public static let defaultExtension = "mlmodelc"

    /// Resolve the URL of a Core ML model by name. Default name is `RealESRGAN_x4plus`.
    public static func defaultModelURL(name: String = defaultModelName,
                                       extension fileExtension: String = defaultExtension) throws -> URL {
        // 1. App bundle (production install — package-app.sh copies Resources/ → .app/Contents/Resources/)
        if let bundleURL = Bundle.main.url(
            forResource: name, withExtension: fileExtension, subdirectory: "models"
        ) {
            return bundleURL
        }

        // 2. Repo dev layout — relative to CWD
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let devURL = cwd
            .appendingPathComponent("Resources/models")
            .appendingPathComponent("\(name).\(fileExtension)")
        if FileManager.default.fileExists(atPath: devURL.path) {
            return devURL
        }

        throw UpscaleError.modelNotFound(name: "\(name).\(fileExtension) (looked in Bundle and \(devURL.path))")
    }

    /// Validate that a candidate URL points to an existing model. A compiled
    /// `.mlmodelc` is a directory bundle; a source `.mlmodel` is a single file.
    /// Both layouts are accepted by `fileExists(atPath:)`.
    public static func validate(modelURL: URL) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw UpscaleError.modelNotFound(name: modelURL.path)
        }
    }
}
