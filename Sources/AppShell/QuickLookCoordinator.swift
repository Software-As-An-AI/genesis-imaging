import AppKit
import Quartz
import Foundation

/// Shared Quick Look panel host — used by `QueueRowView`'s thumbnail tap to
/// surface the upscaled output via the macOS native preview overlay (same UX
/// as space-bar in Finder).
///
/// Singleton because `QLPreviewPanel.shared()` is process-global; multiple
/// rows trying to drive it independently would race. The coordinator holds
/// the current URL and acts as both data source + delegate.
@MainActor
public final class QuickLookCoordinator: NSObject {
    public static let shared = QuickLookCoordinator()

    /// URL currently being previewed. Setter is internal so only `preview(_:)`
    /// mutates it.
    private(set) var currentURL: URL?

    private override init() {
        super.init()
    }

    /// Show the Quick Look panel for `url`. If the panel is already open the
    /// preview swaps in-place (no flicker). On nonexistent files this is a
    /// no-op — Quick Look itself can render a placeholder but we'd rather
    /// fail quietly than show a broken preview.
    public func preview(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        currentURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - QLPreviewPanelDataSource

extension QuickLookCoordinator: @preconcurrency QLPreviewPanelDataSource {
    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentURL == nil ? 0 : 1
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        // QLPreviewItem is implemented by NSURL natively.
        currentURL as NSURL?
    }
}

// MARK: - QLPreviewPanelDelegate

extension QuickLookCoordinator: QLPreviewPanelDelegate {
    // Default behavior is fine; protocol conformance lets the panel route
    // arrow-key / escape events through us without warnings.
}
