import AppKit

/// NSAlert wrapper for the eraser "Kaydet" save destination question:
/// new file vs overwrite vs cancel. Three-button modal — operator-canonical
/// decision 2026-05-16 (defer to customer per save, not a settings choice).
@MainActor
enum SaveDestinationDialog {
    enum Outcome {
        case newFile        // <stem>-edited.png (or auto-increment)
        case overwrite      // replace original
        case cancel         // dismiss dialog, keep sheet open
    }

    /// Present the modal dialog. Returns the customer's choice synchronously.
    /// Default button = `.newFile` (safe, original preserved).
    static func present() -> Outcome {
        let alert = NSAlert()
        alert.messageText = "Düzenlemeleri kaydet"
        alert.informativeText = "Düzenlenmiş çıktıyı nasıl kaydetmek istersin?\n\n"
            + "• Yeni dosya: orijinal upscale çıktısı korunur, edit ayrı bir "
            + "dosya olarak (`-edited` ekiyle) yazılır.\n"
            + "• Üzerine yaz: orijinal upscale çıktısı kalıcı olarak değiştirilir."
        alert.alertStyle = .informational

        // Default (Enter) — safe path
        alert.addButton(withTitle: "Yeni dosya olarak kaydet")
        // Destructive path — flagged style
        let overwriteButton = alert.addButton(withTitle: "Üzerine yaz")
        overwriteButton.hasDestructiveAction = true
        // Cancel (Esc)
        alert.addButton(withTitle: "Vazgeç")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:  return .newFile
        case .alertSecondButtonReturn: return .overwrite
        default:                       return .cancel
        }
    }
}
