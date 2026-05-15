import Foundation
import Darwin

/// Output xattr hygiene: macOS attaches `com.apple.quarantine` to files
/// touched by sandbox-attributed processes — including the **Finder thumbnail
/// generator** that previews newly-written PNGs via Quick Look / Preview
/// extension. Empirical (2026-05-15 Nadezhda customer report): output PNGs
/// pick up quarantine with agent=Preview *after* Genesis Imaging finishes
/// writing, because Finder eagerly renders thumbnails through a sandboxed
/// quicklookd process which attributes its read+attribute write to Preview.
///
/// Web upload pipelines (Canva, Google Drive web, some Etsy uploaders) read
/// that xattr and either refuse the file outright or trigger a "downloaded
/// from internet" challenge — even though the customer never downloaded
/// anything, just upscaled their own coloring book.
///
/// Two layers of defense:
///
/// 1. **Foundation API** (`URLResourceKey.quarantinePropertiesKey = nil`) —
///    Apple-blessed clearance. Removes the quarantine AND tells LaunchServices
///    "this file is not from the internet", preventing subsequent generators
///    (Finder thumbnail, Quick Look) from re-attributing it. This is the
///    canonical path.
///
/// 2. **Raw `removexattr`** as fallback — direct syscall. Used if Foundation
///    setter throws (rare). Doesn't prevent reapply but at least clears the
///    current value.
///
/// Only `com.apple.quarantine` is targeted. Other Apple metadata
/// (`com.apple.macl`, `com.apple.lastuseddate#PS`, `com.apple.provenance`)
/// is legitimate and left intact.
public enum QuarantineUtil {

    /// Best-effort removal of `com.apple.quarantine` from `url`. Tries the
    /// Foundation `URLResourceKey.quarantinePropertiesKey` setter first (which
    /// also prevents reapply via LaunchServices), falls back to raw
    /// `removexattr(2)` if Foundation refuses.
    ///
    /// - Returns: `true` if at least one strip method reported success.
    ///   Silent on failure overall — the file is still usable, just may show
    ///   grey in Finder / trigger an upload dialog on some web pickers.
    @discardableResult
    public static func stripQuarantine(at url: URL) -> Bool {
        // Path 1: Foundation API — also prevents reapply.
        // Setting quarantineProperties to nil clears the attribute and tells
        // LaunchServices the file is clean.
        let nsURL = url as NSURL
        var foundationOK = false
        do {
            try nsURL.setResourceValue(NSNull(),
                                       forKey: .quarantinePropertiesKey)
            foundationOK = true
        } catch {
            // Some volumes / file systems refuse — fall through to raw call.
        }

        // Path 2: Raw removexattr fallback — covers cases Foundation rejected.
        let rawOK: Bool = url.path.withCString { cpath in
            let rc = removexattr(cpath, "com.apple.quarantine", 0)
            return rc == 0 || errno == ENOATTR
        }

        return foundationOK || rawOK
    }
}
