import Foundation
import ImagingCore

/// Locates the ncnn-vulkan binary and bundled models directory.
/// Looks in two places (in order):
///   1. App bundle: `<MainBundle>/Contents/Resources/bin/realesrgan-ncnn-vulkan` (production)
///   2. Repo dev layout: `<CWD>/Resources/bin/realesrgan-ncnn-vulkan` (swift run / swift test)
public enum BinaryLocator {
    public static let binaryName = "realesrgan-ncnn-vulkan"

    public static func defaultBinaryURL() throws -> URL {
        // 1. App bundle (production install)
        if let bundleURL = Bundle.main.url(
            forResource: binaryName, withExtension: nil, subdirectory: "bin"
        ) {
            return bundleURL
        }

        // 2. Repo dev layout — relative to CWD
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let devURL = cwd.appendingPathComponent("Resources/bin/\(binaryName)")
        if FileManager.default.isExecutableFile(atPath: devURL.path) {
            return devURL
        }

        throw UpscaleError.binaryNotFound(path: devURL.path)
    }

    public static func defaultModelsDirectory() throws -> URL {
        // 1. App bundle
        if let bundleURL = Bundle.main.url(
            forResource: "models", withExtension: nil, subdirectory: "bin"
        ) {
            return bundleURL
        }

        // 2. Repo dev layout
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let devURL = cwd.appendingPathComponent("Resources/bin/models")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: devURL.path, isDirectory: &isDir),
           isDir.boolValue {
            return devURL
        }

        throw UpscaleError.modelNotFound(name: "models directory at \(devURL.path)")
    }

    /// Validate that a candidate URL is an executable file. Throws `binaryNotFound` otherwise.
    public static func validate(binaryURL: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw UpscaleError.binaryNotFound(path: binaryURL.path)
        }
    }
}
