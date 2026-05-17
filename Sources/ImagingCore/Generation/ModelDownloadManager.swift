import Foundation
import Observation

/// First-launch download orchestration for the SDXL + Line-Art LoRA model
/// bundle. v0.4.0.0 ships the scaffold (presence check + phase enum +
/// observable progress); actual `URLSession` download wiring lands in
/// v0.4.0.1 once the Hugging Face URLs + SHA256 pins are finalized.
///
/// State machine:
///   .idle → .downloading(progress) → .compiling → .ready
///                                  ↘ .failed(error)
///
/// `checkPresence()` reads `Resources/models/.sdxl-version` marker;
/// `startDownload()` triggers the URLSession transfer + xcrun coremlcompiler
/// post-process. Cancellation supported (URLSession task cancel + cleanup).
///
/// Bundle layout target (~5-6 GB compiled `.mlmodelc`):
///   Resources/models/sdxl/
///     ├── TextEncoder.mlmodelc
///     ├── TextEncoder2.mlmodelc
///     ├── Unet.mlmodelc       ← line-art LoRA merged
///     ├── VaeDecoder.mlmodelc
///     └── .sdxl-version       ← version marker (e.g. "1.0.0-coloring-lora")
@MainActor
@Observable
public final class ModelDownloadManager {
    public static let shared = ModelDownloadManager()

    public enum Phase: Equatable, Sendable {
        case idle
        case downloading(progress: Double, etaSeconds: Int?)
        case compiling
        case ready
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle

    /// Expected bundle version marker. Single source of truth for "is the
    /// installed model the version this app build expects?". Bumping this
    /// forces a re-download on next launch.
    public let expectedVersion: String = "sdxl-1.0.0-coloring-lora-v1"

    /// Bundle root directory. Defaults to the user's Application Support
    /// directory under "GenesisImaging/models/sdxl". Created lazily on
    /// first download attempt.
    public let bundleDirectory: URL = ModelDownloadManager.defaultBundleDirectory()

    private static func defaultBundleDirectory() -> URL {
        let fm = FileManager.default
        let support = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        return support
            .appendingPathComponent("GenesisImaging", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("sdxl", isDirectory: true)
    }

    private init() {}

    // MARK: - Presence

    /// `true` if the bundle directory contains the expected version marker
    /// AND all required `.mlmodelc` directories. Used at app launch to
    /// decide whether to surface the download sheet.
    public func isInstalled() -> Bool {
        let marker = bundleDirectory.appendingPathComponent(".sdxl-version")
        guard FileManager.default.fileExists(atPath: marker.path),
              let stored = try? String(contentsOf: marker, encoding: .utf8)
        else { return false }
        guard stored.trimmingCharacters(in: .whitespacesAndNewlines) == expectedVersion
        else { return false }
        let required = ["TextEncoder.mlmodelc", "TextEncoder2.mlmodelc",
                        "Unet.mlmodelc", "VaeDecoder.mlmodelc"]
        return required.allSatisfy {
            FileManager.default.fileExists(
                atPath: bundleDirectory.appendingPathComponent($0).path
            )
        }
    }

    /// Sync the cached `SettingsStore.sdModelAvailable` flag with current
    /// disk state. Call from app launch + after download completion.
    public func refreshAvailabilityCache() {
        let installed = isInstalled()
        SettingsStore.shared.sdModelAvailable = installed
        phase = installed ? .ready : .idle
    }

    // MARK: - Download (scaffold)

    /// Trigger the first-launch download + compile sequence. Current build
    /// ships only the scaffold (UI + state machine + presence check); the
    /// real URLSession + xcrun coremlcompiler pipeline lands in the next
    /// minor (Phase A.2) once the Hugging Face mirror URLs + SHA256 pins
    /// are recorded in scripts/fetch-sdxl-coreml-model.sh.
    public func startDownload() async {
        phase = .downloading(progress: 0.0, etaSeconds: nil)
        // Give the UI one tick to render the spinner before we collapse to
        // the explanation — otherwise the button press feels like a no-op.
        try? await Task.sleep(nanoseconds: 300_000_000)
        phase = .failed(message: "Görüntü oluşturma arayüzü hazır ama model indirme kanalı henüz açılmadı — bir sonraki sürümde gerçek indirme + SDXL kullanıma alınacak. Beklerken Üret bölümünü gezebilir, slider'ları + prompt formatını deneyebilirsiniz.")
    }

    /// Cancel an in-flight download. v0.4.0.0 no-op (no real download yet).
    public func cancelDownload() {
        phase = .idle
    }

    /// Remove the installed bundle (manual re-download from Settings).
    /// Destructive — caller should confirm with the operator.
    public func uninstall() {
        try? FileManager.default.removeItem(at: bundleDirectory)
        refreshAvailabilityCache()
    }
}
