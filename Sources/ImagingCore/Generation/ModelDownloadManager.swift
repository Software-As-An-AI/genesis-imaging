import Foundation
import Observation

/// First-launch download orchestration for SDXL Core ML bundles.
///
/// Apple's pre-compiled `coreml-stable-diffusion-mixed-bit-palettization`
/// bundle and the Phase A.3 ColoringBook LoRA-fused bundle are each fetched
/// on the customer's first generation attempt for that variant, then
/// persisted under
/// `~/Library/Application Support/GenesisImaging/models/<variant>/` so the
/// DMG stays small. Variants coexist on disk — switching the active variant
/// in Settings does NOT redownload if the target is already installed.
///
/// Phase state machine, per variant:
///   .idle
///     → .downloading(bytes, total, throughput, eta)
///       → .verifying       (SHA256 streaming over zip)
///         → .extracting    (unzip into bundle dir)
///           → .ready
///   any-state → .failed(message)
///   .downloading → .idle  (cancel)
///
/// Single source of truth for bundle URL/SHA/size/marker lives in
/// `SDXLModelCatalog`. Currently-active variant is read from
/// `SettingsStore.sdxlModelVariant`; backward-compat tek-variant accessors
/// (`phase`, `bundleDirectory`, `isInstalled()`, `startDownload()`, …) all
/// resolve to that variant.
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

    // MARK: - Per-variant storage

    private var phases: [SDXLModelCatalog.Variant: Phase] = [:]
    private var activeDownloaders: [SDXLModelCatalog.Variant: ModelDownloader] = [:]

    private init() {}

    // MARK: - Currently-selected variant (compat layer)

    /// Variant the UI currently targets — comes from
    /// `SettingsStore.sdxlModelVariant`. Defaults to `.palettized` for
    /// users upgrading from v0.4.x (preserves the Apple base they already
    /// have on disk).
    public var variant: SDXLModelCatalog.Variant {
        SettingsStore.shared.sdxlModelVariantTyped
    }

    /// Compat: legacy `phase` reads the current variant's phase.
    public var phase: Phase { phase(for: variant) }

    /// Compat: legacy expected pin metadata for the current variant.
    public var expectedVersion: String { variant.versionMarker }
    public var expectedSizeBytes: Int64 { variant.expectedSizeBytes }

    /// Compat: legacy bundle dir for the current variant.
    public var bundleDirectory: URL { bundleDirectory(for: variant) }

    /// Compat: legacy resources dir for the current variant.
    public var resourcesDirectory: URL { resourcesDirectory(for: variant) }

    // MARK: - Per-variant paths

    /// Root directory holding all variant subdirectories.
    public static var modelsRootDirectory: URL { defaultModelsRoot() }

    /// Per-variant bundle root. Palettized keeps the legacy `sdxl/` path so
    /// users upgrading from v0.4.x don't re-download the 6.71 GB Apple
    /// bundle.
    public func bundleDirectory(for variant: SDXLModelCatalog.Variant) -> URL {
        Self.modelsRootDirectory.appendingPathComponent(
            Self.subdirName(for: variant),
            isDirectory: true
        )
    }

    /// Resources sub-path resolved under the variant's bundle dir. The path
    /// to hand to `StableDiffusionXLPipeline(resourcesAt:)`.
    public func resourcesDirectory(for variant: SDXLModelCatalog.Variant) -> URL {
        bundleDirectory(for: variant)
            .appendingPathComponent(variant.resourcesSubpath, isDirectory: true)
    }

    private static func subdirName(for variant: SDXLModelCatalog.Variant) -> String {
        switch variant {
        case .palettized:     return "sdxl"             // legacy v0.4.x layout
        case .base:           return "sdxl-base"
        case .iosSplitEinsum: return "sdxl-ios"
        case .loraColoring:   return "sdxl-lora-coloring"
        case .fluxKlein:      return "flux-klein"      // Phase A.4 — flux-2-swift-mlx
        }
    }

    private static func defaultModelsRoot() -> URL {
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
    }

    // MARK: - Phase access

    /// Per-variant phase. SwiftUI views observing this Manager re-render
    /// when any tracked variant's phase changes.
    public func phase(for variant: SDXLModelCatalog.Variant) -> Phase {
        phases[variant] ?? .idle
    }

    private func setPhase(_ phase: Phase, for variant: SDXLModelCatalog.Variant) {
        phases[variant] = phase
    }

    // MARK: - Presence

    /// Compat: legacy `isInstalled()` checks the current variant.
    public func isInstalled() -> Bool {
        isInstalled(for: variant)
    }

    /// `true` if the variant's bundle directory contains the expected version
    /// marker AND every required entry from the variant's `requiredEntries`
    /// (checked under `resourcesDirectory(for:)`, not the raw extraction
    /// root — Apple/our zips nest one or two folders deep).
    public func isInstalled(for variant: SDXLModelCatalog.Variant) -> Bool {
        let bundleDir = bundleDirectory(for: variant)
        let marker = bundleDir.appendingPathComponent(".sdxl-version")
        guard FileManager.default.fileExists(atPath: marker.path),
              let stored = try? String(contentsOf: marker, encoding: .utf8)
        else { return false }
        guard stored.trimmingCharacters(in: .whitespacesAndNewlines) == variant.versionMarker
        else { return false }
        let resources = resourcesDirectory(for: variant)
        return variant.requiredEntries.allSatisfy { entry in
            FileManager.default.fileExists(
                atPath: resources.appendingPathComponent(entry).path
            )
        }
    }

    /// Sync per-variant cached state with disk truth. Call from app launch
    /// + after any download completion. Sets `phase = .ready` for installed
    /// variants and `.idle` for absent ones (overwrites stale state). The
    /// legacy `SettingsStore.sdModelAvailable` getter is computed from the
    /// currently-selected variant's truth, so no mirror flag to sync.
    public func refreshAvailabilityCache() {
        for v in SDXLModelCatalog.Variant.allCases {
            let installed = isInstalled(for: v)
            // Don't clobber an in-flight .downloading / .verifying / .extracting.
            switch phase(for: v) {
            case .downloading, .verifying, .extracting:
                continue
            default:
                setPhase(installed ? .ready : .idle, for: v)
            }
        }
    }

    // MARK: - Download

    /// Compat: legacy `startDownload()` triggers download of the currently-
    /// selected variant.
    public func startDownload() async {
        await startDownload(for: variant)
    }

    /// Kick the full download → verify → extract pipeline for the given
    /// variant. Idempotent if already running. Already-installed bundles
    /// short-circuit to `.ready`.
    public func startDownload(for variant: SDXLModelCatalog.Variant) async {
        if isInstalled(for: variant) {
            setPhase(.ready, for: variant)
            return
        }
        switch phase(for: variant) {
        case .downloading, .verifying, .extracting:
            return
        default:
            break
        }

        // Phase A.4 dispatch: SDXL variants use the single-zip download path
        // (Phase A.2 logic, unchanged). FLUX variants use the new multi-file
        // path (Step 3) — transformer + model_index sequentially placed at
        // their bundleDir-relative destinations, no unzip step.
        switch variant.engineKind {
        case .coreMLSDXL:
            startSingleZipDownload(for: variant)
        case .mlxFlux:
            startMultiFileDownload(for: variant)
        }
    }

    private func startSingleZipDownload(for variant: SDXLModelCatalog.Variant) {
        setPhase(.downloading(bytesWritten: 0,
                              totalBytes: variant.expectedSizeBytes,
                              throughputBytesPerSec: nil,
                              etaSeconds: nil),
                 for: variant)

        let url = variant.downloadURL
        let downloader = ModelDownloader(url: url) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(downloaderEvent: event, for: variant)
            }
        }
        activeDownloaders[variant] = downloader
        downloader.start()
    }

    /// FLUX multi-file download: sequential per-file `ModelDownloader`
    /// runs. Progress emit is per-current-file (no aggregate across files
    /// in v1 — Step 6 picker UI surfaces "indirme i/N · <displayName>"
    /// if it wants the breakdown). On all files complete, places each at
    /// its destinationSubpath under `bundleDirectory(for:)`, writes
    /// version marker, flips to `.ready`.
    private func startMultiFileDownload(for variant: SDXLModelCatalog.Variant) {
        let files = variant.downloadFiles
        let bundleDir = bundleDirectory(for: variant)
        try? FileManager.default.createDirectory(
            at: bundleDir, withIntermediateDirectories: true
        )
        setPhase(.downloading(bytesWritten: 0,
                              totalBytes: files.first?.sizeBytes ?? 0,
                              throughputBytesPerSec: nil,
                              etaSeconds: nil),
                 for: variant)
        downloadNextFluxFile(for: variant, files: files, index: 0)
    }

    private func downloadNextFluxFile(
        for variant: SDXLModelCatalog.Variant,
        files: [DownloadFile],
        index: Int
    ) {
        guard index < files.count else {
            // All files downloaded — verify + mark ready.
            setPhase(.verifying, for: variant)
            Task.detached { [weak self] in
                await self?.finalizeFluxDownload(variant: variant, files: files)
            }
            return
        }

        let file = files[index]
        let destURL = bundleDirectory(for: variant)
            .appendingPathComponent(file.destinationSubpath, isDirectory: false)
        try? FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Short-circuit if file already exists at destination with correct size.
        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path),
           let attrs = try? fm.attributesOfItem(atPath: destURL.path),
           let size = attrs[.size] as? Int64,
           size == file.sizeBytes {
            downloadNextFluxFile(for: variant, files: files, index: index + 1)
            return
        }

        let downloader = ModelDownloader(url: file.url) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFluxFileEvent(
                    event,
                    variant: variant,
                    files: files,
                    index: index,
                    destURL: destURL
                )
            }
        }
        activeDownloaders[variant] = downloader
        downloader.start()
    }

    private func handleFluxFileEvent(
        _ event: ModelDownloader.Event,
        variant: SDXLModelCatalog.Variant,
        files: [DownloadFile],
        index: Int,
        destURL: URL
    ) {
        switch event {
        case .progress(let bytes, _, let throughput, let eta):
            // Use the per-file totalBytes from catalog for stability — the
            // remote may not report content-length (especially HF redirects).
            setPhase(.downloading(bytesWritten: bytes,
                                  totalBytes: files[index].sizeBytes,
                                  throughputBytesPerSec: throughput,
                                  etaSeconds: eta),
                     for: variant)
        case .finished(let tmpURL):
            // Move tmp file to destination.
            do {
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tmpURL, to: destURL)
            } catch {
                setPhase(
                    .failed(message: "Dosya yerleştirilemedi: \(error.localizedDescription)"),
                    for: variant
                )
                activeDownloaders[variant] = nil
                return
            }
            activeDownloaders[variant] = nil
            // Advance to next file.
            downloadNextFluxFile(for: variant, files: files, index: index + 1)
        case .cancelled:
            setPhase(.idle, for: variant)
            activeDownloaders[variant] = nil
        case .failed(let message):
            setPhase(.failed(message: message), for: variant)
            activeDownloaders[variant] = nil
        }
    }

    private nonisolated func finalizeFluxDownload(
        variant: SDXLModelCatalog.Variant,
        files: [DownloadFile]
    ) async {
        let bundleDir = await MainActor.run { self.bundleDirectory(for: variant) }

        // Per-file SHA verify (where pinned). Skipped for files with sha256 == nil.
        for file in files where file.sha256 != nil {
            let path = bundleDir.appendingPathComponent(
                file.destinationSubpath, isDirectory: false
            )
            do {
                let actual = try ArchiveExtractor.streamingSHA256(of: path)
                guard actual.caseInsensitiveCompare(file.sha256!) == .orderedSame else {
                    await MainActor.run {
                        self.setPhase(
                            .failed(message: "SHA256 mismatch: \(file.displayName) " +
                                    "(beklenen \(file.sha256!.prefix(12))…, " +
                                    "gerçek \(actual.prefix(12))…)"),
                            for: variant
                        )
                    }
                    return
                }
            } catch {
                await MainActor.run {
                    self.setPhase(
                        .failed(message: "SHA256 hesaplanamadı: \(error.localizedDescription)"),
                        for: variant
                    )
                }
                return
            }
        }

        // Write marker. Multi-file variants share the same marker mechanism
        // as single-zip variants — presence + correct version string gates
        // isInstalled.
        do {
            try variant.versionMarker
                .write(to: bundleDir.appendingPathComponent(".sdxl-version"),
                       atomically: true, encoding: .utf8)
        } catch {
            await MainActor.run {
                self.setPhase(
                    .failed(message: "Sürüm işareti yazılamadı: \(error.localizedDescription)"),
                    for: variant
                )
            }
            return
        }

        // Truth check: isInstalled now confirms presence + version marker.
        let trulyInstalled = await MainActor.run { self.isInstalled(for: variant) }
        if trulyInstalled {
            await MainActor.run {
                self.setPhase(.ready, for: variant)
            }
        } else {
            await MainActor.run {
                self.setPhase(
                    .failed(message: "Çoklu-dosya indirme tamamlandı ama isInstalled false — beklenen dosyalardan biri eksik."),
                    for: variant
                )
            }
        }
    }

    /// Compat: legacy `cancelDownload()` cancels the current variant's run.
    public func cancelDownload() {
        cancelDownload(for: variant)
    }

    /// Cancel an in-flight download for the given variant.
    public func cancelDownload(for variant: SDXLModelCatalog.Variant) {
        activeDownloaders[variant]?.cancel()
        activeDownloaders[variant] = nil
        // `.cancel()` emits `.cancelled` → handler resets phase to .idle
    }

    /// Compat: legacy `uninstall()` removes the current variant's bundle.
    public func uninstall() {
        uninstall(for: variant)
    }

    /// Remove the variant's installed bundle (manual re-download from
    /// Settings). Destructive — caller should confirm with the operator.
    public func uninstall(for variant: SDXLModelCatalog.Variant) {
        try? FileManager.default.removeItem(at: bundleDirectory(for: variant))
        // Refresh just this variant's phase; don't disturb others.
        setPhase(isInstalled(for: variant) ? .ready : .idle, for: variant)
    }

    // MARK: - Downloader event handling

    private func handle(downloaderEvent event: ModelDownloader.Event,
                        for variant: SDXLModelCatalog.Variant) {
        switch event {
        case .progress(let bytes, let total, let throughput, let eta):
            setPhase(.downloading(bytesWritten: bytes,
                                  totalBytes: total,
                                  throughputBytesPerSec: throughput,
                                  etaSeconds: eta),
                     for: variant)
        case .finished(let zipURL):
            setPhase(.verifying, for: variant)
            Task.detached { [weak self] in
                await self?.verifyAndExtract(zipURL: zipURL, variant: variant)
            }
        case .cancelled:
            setPhase(.idle, for: variant)
            activeDownloaders[variant] = nil
        case .failed(let message):
            setPhase(.failed(message: message), for: variant)
            activeDownloaders[variant] = nil
        }
    }

    private nonisolated func verifyAndExtract(
        zipURL: URL,
        variant: SDXLModelCatalog.Variant
    ) async {
        let bundleDir = await MainActor.run { self.bundleDirectory(for: variant) }

        do {
            try ArchiveExtractor.verifyAndExtract(
                zipURL: zipURL,
                expectedSHA256: variant.sha256,
                destinationDir: bundleDir,
                expectedSizeBytes: variant.expectedSizeBytes
            )
            await MainActor.run { self.setPhase(.extracting, for: variant) }

            // Marker write happens AFTER extract success
            try variant.versionMarker
                .write(to: bundleDir.appendingPathComponent(".sdxl-version"),
                       atomically: true, encoding: .utf8)

            try? FileManager.default.removeItem(at: zipURL)

            // Trust isInstalled() — not optimistic. Catches structural
            // mismatches (e.g. archive layout drift, missing tokenizer)
            // instead of advertising .ready and failing at first inference.
            // Lesson from v0.4.1.0 → v0.4.1.1 dissonance.
            let trulyInstalled = await MainActor.run { self.isInstalled(for: variant) }
            if trulyInstalled {
                await MainActor.run {
                    self.setPhase(.ready, for: variant)
                    self.activeDownloaders[variant]?.cleanup()
                    self.activeDownloaders[variant] = nil
                }
            } else {
                await MainActor.run {
                    self.setPhase(
                        .failed(message: "Arşiv açıldı ama beklenen dosyalar bulunamadı — bundle yapısı değişmiş olabilir. Kaldır + tekrar indir denemeden destek isteyin."),
                        for: variant
                    )
                    self.activeDownloaders[variant] = nil
                }
            }
        } catch {
            let message: String = {
                if let e = error as? ArchiveExtractor.ExtractError { return e.description }
                return error.localizedDescription
            }()
            await MainActor.run {
                self.setPhase(.failed(message: message), for: variant)
                self.activeDownloaders[variant] = nil
            }
        }
    }
}
