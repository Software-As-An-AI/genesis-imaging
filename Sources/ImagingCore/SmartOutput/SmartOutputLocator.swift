import Foundation

/// Locates the bundled `pngquant` + `oxipng` binaries used by `SmartOutputProcessor`.
///
/// Lookup order (mirrors `NcnnEngine`'s `BinaryLocator`):
/// 1. App bundle: `<MainBundle>/Contents/Resources/bin/<name>` (production)
/// 2. Repo dev layout: `<CWD>/Resources/bin/<name>` (swift run / swift test)
///
/// Returns `nil` if not found — callers degrade gracefully in `.auto` mode
/// (skip post-process) or surface a preflight error in `.always` mode.
public enum SmartOutputLocator {
    public static let pngquantName = "pngquant"
    public static let oxipngName = "oxipng"

    /// Locate the bundled `pngquant` binary. Returns `nil` if unavailable.
    public static func pngquantURL() -> URL? {
        locate(binaryName: pngquantName)
    }

    /// Locate the bundled `oxipng` binary. Returns `nil` if unavailable.
    public static func oxipngURL() -> URL? {
        locate(binaryName: oxipngName)
    }

    /// True iff both binaries are present in the expected location.
    public static func bothAvailable() -> Bool {
        pngquantURL() != nil && oxipngURL() != nil
    }

    // MARK: - Internals

    private static func locate(binaryName: String) -> URL? {
        // 1. App bundle (production install)
        if let bundleURL = Bundle.main.url(
            forResource: binaryName, withExtension: nil, subdirectory: "bin"
        ), FileManager.default.isExecutableFile(atPath: bundleURL.path) {
            return bundleURL
        }

        // 2. Repo dev layout — relative to CWD
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let devURL = cwd.appendingPathComponent("Resources/bin/\(binaryName)")
        if FileManager.default.isExecutableFile(atPath: devURL.path) {
            return devURL
        }

        return nil
    }
}
