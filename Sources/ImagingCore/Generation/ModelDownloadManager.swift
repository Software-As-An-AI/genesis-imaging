import Foundation
import Observation

/// First-launch download orchestration for the SDXL Core ML bundle.
///
/// Apple's pre-compiled `coreml-stable-diffusion-mixed-bit-palettization`
/// bundle (6.71 GB zip → ~6 GB of `.mlmodelc` directories) is fetched on
/// the customer's first generation attempt and persisted under
/// `~/Library/Application Support/GenesisImaging/models/sdxl/` so the DMG
/// stays small.
///
/// Phase state machine:
///   .idle
///     → .downloading(bytes, total, eta, throughput)
///       → .verifying       (SHA256 streaming over zip)
///         → .extracting    (unzip into bundle dir)
///           → .ready
///   any-state → .failed(message)
///   .downloading → .idle  (cancel)
///
/// Single source of truth for bundle URL/SHA/size/marker lives in
/// `SDXLModelCatalog`. Variant pinned via `SDXLModelCatalog.defaultVariant`.
@MainActor
@Observable
public final class ModelDownloadManager {
    public static let shared = ModelDownloadManager()

    public enum Phase: Equatable, Sendable {
        case idle
        /// `bytesWritten` and `totalBytes` are file-level (zip download).
        /// `throughputBytesPerSec` may be nil during ramp-up. `etaSeconds`
        /// capped at 99 × 60 by `ModelDownloader`.
        case downloading(bytesWritten: Int64, totalBytes: Int64,
                         throughputBytesPerSec: Double?, etaSeconds: Int?)
        case verifying
        case extracting
        case ready
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle

    /// Currently shipping variant — derived from `SDXLModelCatalog` so the
    /// catalog stays the only place to bump versions. Bumping the variant
    /// (or its `versionMarker`) forces a re-download on next launch.
    public var variant: SDXLModelCatalog.Variant { SDXLModelCatalog.defaultVariant }

    public var expectedVersion: String { variant.versionMarker }

    public var expectedSizeBytes: Int64 { variant.expectedSizeBytes }

    /// Bundle root directory. Lives under user-domain Application Support so
    /// users can inspect / delete via Finder if needed (Settings exposes a
    /// "Reveal in Finder" affordance).
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

    private var activeDownloader: ModelDownloader?

    private init() {}

    // MARK: - Presence

    /// `true` if the bundle directory contains the expected version marker
    /// AND every required entry from `SDXLModelCatalog.Variant.requiredEntries`.
    /// Used at app launch + before every generation attempt.
    public func isInstalled() -> Bool {
        let marker = bundleDirectory.appendingPathComponent(".sdxl-version")
        guard FileManager.default.fileExists(atPath: marker.path),
              let stored = try? String(contentsOf: marker, encoding: .utf8)
        else { return false }
        guard stored.trimmingCharacters(in: .whitespacesAndNewlines) == expectedVersion
        else { return false }
        return variant.requiredEntries.allSatisfy { entry in
            FileManager.default.fileExists(
                atPath: bundleDirectory.appendingPathComponent(entry).path
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

    // MARK: - Download

    /// Kick the full download → verify → extract pipeline. Idempotent if
    /// already running. Already-installed bundles short-circuit to `.ready`.
    public func startDownload() async {
        if isInstalled() {
            phase = .ready
            SettingsStore.shared.sdModelAvailable = true
            return
        }
        if case .downloading = phase { return }
        if case .verifying = phase { return }
        if case .extracting = phase { return }

        phase = .downloading(bytesWritten: 0,
                             totalBytes: expectedSizeBytes,
                             throughputBytesPerSec: nil,
                             etaSeconds: nil)

        let url = variant.downloadURL
        let downloader = ModelDownloader(url: url) { [weak self] event in
            // Delegate queue → MainActor for state mutation.
            Task { @MainActor [weak self] in
                self?.handle(downloaderEvent: event)
            }
        }
        activeDownloader = downloader
        downloader.start()
    }

    /// Cancel an in-flight download. Clears resumeData so the next attempt
    /// starts fresh (transient network failures keep resumeData; explicit
    /// user cancel discards it).
    public func cancelDownload() {
        activeDownloader?.cancel()
        activeDownloader = nil
        // `cancel()` on the downloader emits `.cancelled` → handler resets phase
    }

    /// Remove the installed bundle (manual re-download from Settings).
    /// Destructive — caller should confirm with the operator.
    public func uninstall() {
        try? FileManager.default.removeItem(at: bundleDirectory)
        refreshAvailabilityCache()
    }

    // MARK: - Downloader event handling

    private func handle(downloaderEvent: ModelDownloader.Event) {
        switch downloaderEvent {
        case .progress(let bytes, let total, let throughput, let eta):
            phase = .downloading(bytesWritten: bytes,
                                 totalBytes: total,
                                 throughputBytesPerSec: throughput,
                                 etaSeconds: eta)
        case .finished(let zipURL):
            // Hop off MainActor for SHA256 streaming + unzip (both blocking).
            phase = .verifying
            Task.detached { [weak self] in
                await self?.verifyAndExtract(zipURL: zipURL)
            }
        case .cancelled:
            phase = .idle
            activeDownloader = nil
        case .failed(let message):
            phase = .failed(message: message)
            activeDownloader = nil
        }
    }

    private nonisolated func verifyAndExtract(zipURL: URL) async {
        let v = await MainActor.run { self.variant }
        let bundleDir = await MainActor.run { self.bundleDirectory }
        let expectedSize = await MainActor.run { self.expectedSizeBytes }

        do {
            try ArchiveExtractor.verifyAndExtract(
                zipURL: zipURL,
                expectedSHA256: v.sha256,
                destinationDir: bundleDir,
                expectedSizeBytes: expectedSize
            )
            await MainActor.run { self.phase = .extracting }

            // Marker write happens AFTER extract success
            try v.versionMarker
                .write(to: bundleDir.appendingPathComponent(".sdxl-version"),
                       atomically: true, encoding: .utf8)

            // Cleanup staging zip
            try? FileManager.default.removeItem(at: zipURL)

            await MainActor.run {
                self.phase = .ready
                SettingsStore.shared.sdModelAvailable = true
                self.activeDownloader?.cleanup()
                self.activeDownloader = nil
            }
        } catch {
            let message: String = {
                if let e = error as? ArchiveExtractor.ExtractError { return e.description }
                return error.localizedDescription
            }()
            await MainActor.run {
                self.phase = .failed(message: message)
                self.activeDownloader = nil
            }
        }
    }
}
