import Foundation
import Darwin

/// Output xattr hygiene: macOS sandboxes notarized apps so every file the
/// app writes inherits `com.apple.quarantine`. Web upload pipelines (Canva,
/// Google Drive web, some Etsy uploaders) read that xattr and either refuse
/// the file outright or trigger a "downloaded from internet" challenge
/// dialog before letting it through.
///
/// Genesis Imaging produces user-owned content (the customer upscaled their
/// own coloring books) — the quarantine flag is technically correct (sandbox
/// wrote it) but semantically wrong (customer isn't downloading anything).
/// Strip it on every successful output write so files behave like ordinary
/// user-created PNGs.
///
/// Only `com.apple.quarantine` is removed. Other Apple metadata
/// (`com.apple.macl`, `com.apple.lastuseddate#PS`, `com.apple.provenance`)
/// is legitimate and left intact.
public enum QuarantineUtil {

    /// Best-effort removal of `com.apple.quarantine` from `url`. Silent on
    /// failure — the file is still usable, just may show grey in Finder /
    /// trigger an upload dialog on some web pickers.
    @discardableResult
    public static func stripQuarantine(at url: URL) -> Bool {
        url.path.withCString { cpath in
            // Returns 0 on success, -1 on error. ENOATTR (93) when the xattr
            // isn't present — common when an earlier strip succeeded or the
            // app wasn't sandboxed. Treat both as benign.
            let rc = removexattr(cpath, "com.apple.quarantine", 0)
            return rc == 0 || errno == ENOATTR
        }
    }
}
