import Foundation

/// Detects whether a file/folder URL lives inside an iCloud Drive sync zone.
///
/// Genesis Imaging customer-report (2026-05-15 Nadezhda's machine) surfaced
/// two failure modes from iCloud-synced output dirs:
///
/// 1. **Source files evicted** — `Optimize Mac Storage` evicts inactive
///    files to the cloud, leaving a placeholder. `CGImageSourceCreateWithURL`
///    fails ("CGImageSource create failed") because the byte stream isn't
///    materialized locally; manual `cp`/touch is needed to download.
///
/// 2. **File-provider attribution** — quicklookd renders thumbnails through
///    a sandboxed Preview-extension that reads the file; macOS attributes
///    that read as a "Preview opened it" event and re-attaches
///    `com.apple.quarantine` even after Genesis Imaging strips it. Web
///    upload pipelines (Canva, Drive) then refuse the file.
///
/// Two detection signals — either is sufficient:
///   - `URLResourceKey.isUbiquitousItemKey` → true (Foundation API)
///   - Path prefix match (`~/Library/Mobile Documents/`, or `~/Desktop`/
///     `~/Documents` when "Desktop & Documents Folders" iCloud sync is on)
///
/// Used by `BatchQueueView` to surface a warning banner when the chosen
/// output dir is iCloud-resident, recommending `~/Downloads` or another
/// non-synced location.
public enum CloudLocationDetector {

    /// Verdict for a given URL: nature of the cloud sync, if any.
    public enum Verdict: Sendable, Equatable {
        case nonCloud
        case iCloudDriveContainer            // ~/Library/Mobile Documents/com~apple~CloudDocs/...
        case iCloudDesktopOrDocuments        // ~/Desktop or ~/Documents with iCloud sync on
        case otherFileProvider               // 3rd-party file-provider (Dropbox, OneDrive via FP)

        public var isCloudSynced: Bool { self != .nonCloud }

        public var displayName: String {
            switch self {
            case .nonCloud: return "Local"
            case .iCloudDriveContainer: return "iCloud Drive"
            case .iCloudDesktopOrDocuments: return "iCloud Drive (Masaüstü/Belgeler senkronu)"
            case .otherFileProvider: return "Cloud sync klasörü"
            }
        }

        public var warningMessage: String {
            switch self {
            case .nonCloud:
                return ""
            case .iCloudDriveContainer, .iCloudDesktopOrDocuments, .otherFileProvider:
                return "Bu klasör \(displayName)'inde. Kaynak dosyalar buluta evict edilmişse okuma başarısız olabilir, çıktıdaki quarantine işareti de bazı yükleyicilerde (Canva, Drive web) sorun çıkarabilir. ~/Downloads veya iCloud dışı bir klasör önerilir."
            }
        }
    }

    /// Inspect a URL and return a `Verdict`. Safe to call from any thread;
    /// uses Foundation resource keys + filesystem path comparison.
    public static func inspect(_ url: URL) -> Verdict {
        // Path 1: Foundation resource key (most reliable for files that
        // exist; folders sometimes return false because the URL isn't
        // tracked yet).
        if let isUbiq = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
            .isUbiquitousItem, isUbiq == true {
            // Distinguish CloudDocs container vs Desktop&Documents
            return classifyByPath(url) ?? .iCloudDriveContainer
        }

        // Path 2: Path prefix matching — catches the "folder selected by
        // user that lives under iCloud" case Foundation often misses for
        // unmaterialized parents.
        if let classified = classifyByPath(url) {
            return classified
        }

        return .nonCloud
    }

    /// Pure path inspection — no I/O. Useful for cheap pre-flight checks.
    private static func classifyByPath(_ url: URL) -> Verdict? {
        let path = url.standardizedFileURL.path
        let home = NSHomeDirectory()

        // iCloud Drive container (always present when iCloud Drive enabled)
        if path.contains("/Library/Mobile Documents/") {
            return .iCloudDriveContainer
        }

        // Desktop & Documents Folders sync: when the OS feature is on, the
        // physical Desktop/Documents dirs are symlinks into Mobile Documents.
        // We can't probe the symlink target without root, but we can probe
        // the canonical/standardized path: when sync is on, NSHomeDirectory()
        // points into Mobile Documents itself, OR the realpath of
        // ~/Desktop resolves into Mobile Documents.
        for sub in ["Desktop", "Documents"] {
            let candidate = "\(home)/\(sub)"
            if path == candidate || path.hasPrefix("\(candidate)/") {
                // Resolve symlink to detect actual iCloud backing.
                let resolved = (candidate as NSString)
                    .resolvingSymlinksInPath
                if resolved.contains("Mobile Documents") {
                    return .iCloudDesktopOrDocuments
                }
            }
        }

        return nil
    }
}

// MARK: - Filename heuristics (sibling concern, kept together)

/// Detects whether a filename appears to be the output of a prior Genesis
/// Imaging upscale (carries `-upscaled-` segment). Used by `BatchQueueView`
/// to prompt before re-adding such files — re-upscaling is allowed (operator
/// directive 2026-05-15) but should be opt-in to avoid accidental doubles.
public enum FilenameHeuristics {

    /// True if `url.lastPathComponent` contains the canonical `-upscaled-`
    /// segment Genesis Imaging emits.
    public static func looksLikeAlreadyUpscaled(_ url: URL) -> Bool {
        url.deletingPathExtension().lastPathComponent.contains("-upscaled-")
    }

    /// Partition a URL list into "fresh" (never upscaled) and "already
    /// upscaled" (looks like prior Genesis output). Order within each
    /// partition matches the input order.
    public static func partition(_ urls: [URL]) -> (fresh: [URL], alreadyUpscaled: [URL]) {
        var fresh: [URL] = []
        var dup: [URL] = []
        for u in urls {
            if looksLikeAlreadyUpscaled(u) { dup.append(u) }
            else { fresh.append(u) }
        }
        return (fresh, dup)
    }
}
