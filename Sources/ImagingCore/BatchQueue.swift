import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - Queue Item

/// State a queue item passes through during a batch upscale run.
public enum QueueItemState: String, Sendable, Equatable {
    case pending
    case processing
    case done
    case failed
    case skipped
}

/// A single image enqueued for batch upscaling.
///
/// Pure value-type; UI layer renders thumbnails from `thumbnailData` (raw bytes)
/// to avoid coupling ImagingCore to AppKit's non-`Sendable` `NSImage`. Per-item
/// `modelOverride` / `scaleOverride` are nil by default, in which case the
/// `BatchQueue.defaultModel` / `BatchQueue.defaultScale` apply at processing time.
public struct QueueItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let sourceURL: URL
    public var modelOverride: String?
    public var scaleOverride: Int?
    public var state: QueueItemState
    public var progress: Double
    public var duration: TimeInterval?
    public var outputURL: URL?
    public var errorMessage: String?
    /// Raw thumbnail bytes (e.g. 64×64 PNG/JPEG). UI layer decodes to NSImage.
    public var thumbnailData: Data?

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        modelOverride: String? = nil,
        scaleOverride: Int? = nil,
        state: QueueItemState = .pending,
        progress: Double = 0,
        duration: TimeInterval? = nil,
        outputURL: URL? = nil,
        errorMessage: String? = nil,
        thumbnailData: Data? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.modelOverride = modelOverride
        self.scaleOverride = scaleOverride
        self.state = state
        self.progress = progress
        self.duration = duration
        self.outputURL = outputURL
        self.errorMessage = errorMessage
        self.thumbnailData = thumbnailData
    }

    /// Effective model for this item given the batch default.
    public func effectiveModel(batchDefault: String) -> String {
        modelOverride ?? batchDefault
    }

    /// Effective scale for this item given the batch default.
    public func effectiveScale(batchDefault: Int) -> Int {
        scaleOverride ?? batchDefault
    }
}

// MARK: - Preflight Issue

/// Issue surfaced by `PreflightValidator` before a batch starts processing.
/// Mid-batch surprises (rare OOM, IO race) are NOT preflight issues — they
/// flow through the per-item skip+continue path during `BatchQueue.start()`.
public enum PreflightIssue: Sendable, Equatable {
    case fileMissing(URL)
    case unreadable(URL)
    case undecodable(URL)
    case unsupportedFormat(URL, String)
    case outputNotWritable(URL)
    case diskSpaceInsufficient(needed: Int64, available: Int64)
    case memoryRisk(URL, estimatedMB: Int)
    case modelMissing(String)
}

// MARK: - BatchQueue

/// Coordinates a sequential multi-file upscale run.
///
/// Engine-agnostic: knows nothing about NCNN vs CoreML. The Wave 3 engine
/// wiring injects an `engineProvider` closure at `start(...)` time so this
/// module never imports `NcnnEngine` / `CoreMLEngine` (those depend on
/// `ImagingCore`, not the other way around).
///
/// State machine:
/// ```
/// draft → validating → ready → processing → completed
///                            ↘            ↘
///                             draft        cancelled  (via softCancel)
/// ```
@MainActor
public final class BatchQueue: ObservableObject {
    /// High-level lifecycle state of the queue itself.
    public enum Phase: String, Sendable, Equatable {
        case draft
        case validating
        case ready
        case processing
        case completed
        case cancelled
    }

    // MARK: - Published state

    @Published public var items: [QueueItem] = []
    @Published public var defaultModel: String
    @Published public var defaultScale: Int
    @Published public var batchOutputOverride: URL?
    @Published public var phase: Phase = .draft
    @Published public var startTime: Date?
    @Published public var averageDuration: TimeInterval?
    @Published public var cancelRequested: Bool = false
    @Published public var preflightIssues: [PreflightIssue] = []

    // MARK: - Init

    public init(
        defaultModel: String = "realesrgan-x4plus",
        defaultScale: Int = 4,
        batchOutputOverride: URL? = nil
    ) {
        self.defaultModel = defaultModel
        self.defaultScale = defaultScale
        self.batchOutputOverride = batchOutputOverride
    }

    // MARK: - Mutation

    /// Append `urls` as `pending` items. Same `sourceURL` is dropped (defensive
    /// dedupe — same file dropped twice yields one item, not two).
    ///
    /// Wave 3: also fires a background task to populate `thumbnailData` for
    /// each newly-added item. UI layer can render the placeholder glyph
    /// during the brief window before thumbnails resolve.
    public func add(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let existing = Set(items.map { $0.sourceURL.standardizedFileURL })
        var seenInBatch: Set<URL> = []
        var newlyAddedIDs: [UUID] = []
        for url in urls {
            let key = url.standardizedFileURL
            if existing.contains(key) || seenInBatch.contains(key) { continue }
            seenInBatch.insert(key)
            let item = QueueItem(sourceURL: url)
            items.append(item)
            newlyAddedIDs.append(item.id)
        }
        // Fire background thumbnail generation. Detached + Sendable so we
        // don't block `add(urls:)` on disk I/O.
        let urlsByID: [(UUID, URL)] = newlyAddedIDs.compactMap { id in
            guard let item = self.items.first(where: { $0.id == id }) else { return nil }
            return (id, item.sourceURL)
        }
        if urlsByID.isEmpty { return }
        Task.detached(priority: .utility) { [weak self] in
            for (id, url) in urlsByID {
                let data = Self.makeThumbnailData(for: url)
                guard let data = data else { continue }
                await self?.applyThumbnail(id: id, data: data)
            }
        }
    }

    /// Remove the item with `itemID`. No-op if not found.
    public func remove(itemID: UUID) {
        items.removeAll { $0.id == itemID }
    }

    /// Override model and/or scale for a single item. Pass `nil` to clear.
    /// Caller may set only one of the two by passing the current value for the other.
    public func setOverride(itemID: UUID, model: String?, scale: Int?) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].modelOverride = model
        items[idx].scaleOverride = scale
    }

    /// Request cancellation. Engine loop checks this between items; the
    /// currently-processing item is allowed to finish (soft cancel contract).
    public func softCancel() {
        cancelRequested = true
    }

    /// Reset queue to a pristine draft state so a fresh run can start.
    /// Used by the end-summary "Listeyi temizle" button + any external caller
    /// that wants to recycle the same queue object.
    public func reset() {
        items.removeAll()
        preflightIssues.removeAll()
        cancelRequested = false
        startTime = nil
        averageDuration = nil
        phase = .draft
    }

    // MARK: - Computed

    public var completedCount: Int {
        items.filter { $0.state == .done }.count
    }

    public var totalCount: Int {
        items.count
    }

    /// Estimated seconds remaining, using a flat running average of completed
    /// item durations. Returns `nil` until the first item completes (no signal
    /// to extrapolate from).
    public var etaSeconds: TimeInterval? {
        guard let avg = averageDuration else { return nil }
        let remaining = items.filter { $0.state == .pending || $0.state == .processing }.count
        return TimeInterval(remaining) * avg
    }

    // MARK: - Lifecycle (Wave 3 wiring)

    /// Run pre-flight validation against current `items`. Wave 3: wired to
    /// `PreflightValidator.validate(...)`.
    ///
    /// - Parameter modelsDirectory: Where to look for model files. Pass
    ///   `nil` to skip the model-presence check (engine factory will surface
    ///   missing-model errors at start time).
    public func preflight(modelsDirectory: URL? = nil) async -> [PreflightIssue] {
        phase = .validating
        let validator = PreflightValidator()
        let issues = await validator.validate(
            items: items,
            outputDir: batchOutputOverride,
            defaultModel: defaultModel,
            defaultScale: defaultScale,
            modelsDirectory: modelsDirectory
        )
        preflightIssues = issues
        phase = issues.isEmpty ? .ready : .draft
        return issues
    }

    /// Begin sequential processing using `engineProvider` to construct one
    /// engine per item (provider may cache + return the same engine across
    /// calls — `BatchQueue` doesn't care).
    ///
    /// Soft cancel contract: when `cancelRequested == true`, the queue stops
    /// dispatching NEW items, but the currently-processing engine call is
    /// allowed to finish.
    ///
    /// Failure policy: if any single item throws, mark it `.failed`, record
    /// `errorMessage`, and continue to the next item. The queue completes
    /// `.completed` (or `.cancelled` if soft-cancel was requested) even when
    /// individual items failed — terminal counts live in `endSummary`.
    ///
    /// - Parameters:
    ///   - engineProvider: Async closure that produces an `UpscaleEngine`.
    ///     Called once before the loop starts. If provider throws, the run
    ///     terminates with `.completed` (no items processed) and surfaces the
    ///     error as `errorMessage` on the first item.
    public func start(engineProvider: @Sendable () async throws -> any UpscaleEngine) async {
        guard phase == .ready || phase == .draft else { return }
        phase = .processing
        startTime = Date()
        // Note: cancelRequested is NOT cleared here — a soft-cancel that
        // arrived between preflight + start should still take effect on the
        // very first iteration of the item loop. Use `reset()` to clear.

        // Obtain engine. If construction fails, surface as item-level error
        // on the first pending item so the UI has somewhere to display it.
        let engine: any UpscaleEngine
        do {
            engine = try await engineProvider()
        } catch {
            let message = "Engine init failed: \(error.localizedDescription)"
            if let firstIdx = items.firstIndex(where: { $0.state == .pending }) {
                items[firstIdx].state = .failed
                items[firstIdx].errorMessage = message
            }
            phase = .completed
            return
        }

        // Sequential item loop.
        for idx in items.indices {
            // Soft-cancel check between items.
            if cancelRequested { break }
            // Skip non-pending items (re-run scenarios may have residue).
            if items[idx].state != .pending { continue }

            await processItem(at: idx, engine: engine)
        }

        phase = cancelRequested ? .cancelled : .completed
    }

    /// Backwards-compatible parameterless start used by Wave 1/2 tests that
    /// only need phase transitions. Equivalent to `start { fatalError() }`
    /// without ever calling the provider (no items to process).
    public func start() async {
        guard phase == .ready || phase == .draft else { return }
        phase = .processing
        startTime = Date()
        // No engine wiring — Wave 1 phase-transition test compatibility only.
    }

    // MARK: - Engine processing

    /// Process a single item via `engine`. Engine writes output to a `.tmp`
    /// neighbour of the resolved final URL; on success the tmp is moved
    /// atomically into place. On any throw, item is marked `.failed` with
    /// `errorMessage` set.
    private func processItem(at idx: Int, engine: any UpscaleEngine) async {
        items[idx].state = .processing
        items[idx].progress = 0
        let item = items[idx]

        let model = item.effectiveModel(batchDefault: defaultModel)
        let scale = item.effectiveScale(batchDefault: defaultScale)
        let smartMode = SettingsStore.shared.smartOutputMode
        let finalURL = OutputWriter.resolveOutputURL(
            source: item.sourceURL,
            scale: scale,
            batchOverride: batchOutputOverride,
            smartOutputTag: smartMode.filenameTag
        )
        let tmpURL = finalURL.deletingLastPathComponent()
            .appendingPathComponent("\(finalURL.lastPathComponent).tmp.\(UUID().uuidString)")

        let request = UpscaleRequest(
            inputURL: item.sourceURL,
            outputURL: tmpURL,
            modelName: model,
            scale: scale
        )

        let runStart = Date()
        do {
            try await runEngineStream(engine: engine, request: request, itemIndex: idx)

            // Post-process: palette-aware compression on tmpURL before atomic
            // move. Engine already succeeded — if smart output throws, log and
            // proceed with the un-optimized tmp file (engine's work is intact).
            let smartMode = SettingsStore.shared.smartOutputMode
            let despeckleEnabled = SettingsStore.shared.despeckleEnabled
            let despecklePreset = DespecklePreset.from(
                rawValue: SettingsStore.shared.despecklePreset
            )
            let lineArtEnhanceEnabled = SettingsStore.shared.lineArtEnhanceEnabled
            let lineArtEnhancePreset = LineArtEnhancePreset.from(
                rawValue: SettingsStore.shared.lineArtEnhancePreset
            )
            var resolvedFinalURL = finalURL
            if smartMode != .off {
                do {
                    let pr = try SmartOutputProcessor().process(
                        url: tmpURL,
                        mode: smartMode,
                        despeckleEnabled: despeckleEnabled,
                        despecklePreset: despecklePreset,
                        lineArtEnhanceEnabled: lineArtEnhanceEnabled,
                        lineArtEnhancePreset: lineArtEnhancePreset
                    )
                    if smartMode == .adaptive, let picked = pr.adaptivePicked {
                        resolvedFinalURL = Self.swapAdaptiveTag(
                            finalURL,
                            with: picked,
                            despecklePreset: pr.appliedDespecklePreset,
                            enhancePreset: pr.appliedLineArtEnhancePreset
                        )
                    } else if pr.appliedDespecklePreset != nil || pr.appliedLineArtEnhancePreset != nil {
                        resolvedFinalURL = Self.appendPostProcessSuffix(
                            finalURL,
                            despecklePreset: pr.appliedDespecklePreset,
                            enhancePreset: pr.appliedLineArtEnhancePreset
                        )
                    }
                } catch {
                    FileHandle.standardError.write(Data(
                        "[smart-output] post-process failed (non-fatal): \(error)\n".utf8
                    ))
                }
            }

            // Engine wrote bytes to tmpURL — promote atomically.
            try Self.atomicMove(from: tmpURL, to: resolvedFinalURL)

            let duration = Date().timeIntervalSince(runStart)
            items[idx].state = .done
            items[idx].progress = 1.0
            items[idx].duration = duration
            items[idx].outputURL = resolvedFinalURL
            items[idx].errorMessage = nil
            recordCompletion(duration: duration)
        } catch {
            // Clean up any stray tmp file before recording failure.
            try? FileManager.default.removeItem(at: tmpURL)
            items[idx].state = .failed
            items[idx].errorMessage = describe(error)
        }
    }

    /// Consume the engine's progress stream + drive `item.progress` updates.
    /// Throws on engine failure; returns normally on `.completed`.
    private func runEngineStream(
        engine: any UpscaleEngine,
        request: UpscaleRequest,
        itemIndex idx: Int
    ) async throws {
        let stream = engine.upscale(request: request)
        var sawCompleted = false
        for try await event in stream {
            switch event {
            case .started:
                items[idx].progress = 0
            case .tile(let current, let total):
                items[idx].progress = total > 0
                    ? Double(current) / Double(total)
                    : 0
            case .percentage(let pct):
                items[idx].progress = max(0, min(1, pct / 100.0))
            case .completed:
                items[idx].progress = 1.0
                sawCompleted = true
            case .failed(let err):
                throw err
            }
        }
        if !sawCompleted {
            // Engine ended stream without explicit completion + without throw —
            // treat as failure so we don't silently mark the item .done.
            throw UpscaleError.engineFailure(
                exitCode: -1,
                stderr: "Engine stream ended without completion event"
            )
        }
    }

    /// Atomic same-volume move (rename(2) on macOS). Both ends must share the
    /// same parent directory — `processItem` constructs `tmpURL` as a
    /// neighbour of `finalURL` so this is always true.
    ///
    /// Side-effect: strips `com.apple.quarantine` xattr from the destination
    /// after the move. Sandboxed/notarized apps inherit quarantine on every
    /// write; this xattr blocks web upload pipelines (Canva, Drive web) for
    /// customer-owned content. See `QuarantineUtil`.
    private static func atomicMove(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try? fm.removeItem(at: dst)
        }
        try fm.moveItem(at: src, to: dst)
        QuarantineUtil.stripQuarantine(at: dst)
    }

    /// Append `-clean-<preset>` and/or `-enhanced` to a non-adaptive
    /// filename. Used when manual `.binarize`/`.colors8` mode triggers
    /// despeckle and/or line art enhance — distinct names per option
    /// combination so A/B comparisons don't collide via auto-increment.
    static func appendPostProcessSuffix(
        _ url: URL,
        despecklePreset: DespecklePreset?,
        enhancePreset: LineArtEnhancePreset?
    ) -> URL {
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let cleanPart = despecklePreset.map { "-clean-\($0.rawValue)" } ?? ""
        let enhancePart = enhancePreset.map { "-enhanced-\($0.rawValue)" } ?? ""
        let suffix = cleanPart + enhancePart
        if suffix.isEmpty || stem.contains(suffix) { return url }
        let newStem = "\(stem)\(suffix)"
        let candidate = dir.appendingPathComponent(newStem).appendingPathExtension(ext)
        let fm = FileManager.default
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var counter = 2
        while counter < 10_000 {
            let c = dir.appendingPathComponent("\(newStem)-\(counter)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: c.path) { return c }
            counter += 1
        }
        return candidate
    }

    /// Swap the trailing `-adaptive` segment of `url`'s filename with
    /// `-adaptive-<pickedTag>` and optionally append `-clean-<preset>` when
    /// despeckle ran. Used when `.adaptive` mode resolved to a concrete
    /// sub-mode so the on-disk filename advertises both the routing decision
    /// AND the applied cleanup preset (so 3-preset A/B comparisons don't
    /// collide via auto-increment).
    ///
    /// Resolves collisions by auto-incrementing — never overwrites an
    /// existing file at the rewritten path.
    static func swapAdaptiveTag(
        _ url: URL,
        with picked: SmartOutputMode,
        despecklePreset: DespecklePreset? = nil,
        enhancePreset: LineArtEnhancePreset? = nil
    ) -> URL {
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let pickedTag = picked.filenameTag ?? "lossless"
        let cleanSuffix = despecklePreset.map { "-clean-\($0.rawValue)" } ?? ""
        let enhancedSuffix = enhancePreset.map { "-enhanced-\($0.rawValue)" } ?? ""
        let postSuffix = cleanSuffix + enhancedSuffix

        var newStem: String
        if let range = stem.range(of: "-adaptive") {
            let after = stem[range.upperBound...]
            newStem = String(stem[..<range.upperBound]) + "-\(pickedTag)" + postSuffix + String(after)
        } else {
            newStem = "\(stem)-\(pickedTag)\(postSuffix)"
        }

        let candidate = dir.appendingPathComponent(newStem).appendingPathExtension(ext)
        let fm = FileManager.default
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        var counter = 2
        while counter < 10_000 {
            let alt = dir.appendingPathComponent("\(newStem)-\(counter)")
                .appendingPathExtension(ext)
            if !fm.fileExists(atPath: alt.path) {
                return alt
            }
            counter += 1
        }
        return candidate
    }

    private func describe(_ error: Error) -> String {
        if let upscaleErr = error as? UpscaleError {
            switch upscaleErr {
            case .binaryNotFound(let path):
                return "Engine binary not found: \(path)"
            case .modelNotFound(let name):
                return "Model not found: \(name)"
            case .unsupportedFormat(let mediaType):
                return "Unsupported format: \(mediaType)"
            case .engineFailure(let exitCode, let stderr):
                let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let snippet = trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
                return snippet.isEmpty
                    ? "Engine failed (exit \(exitCode))"
                    : "Engine failed (exit \(exitCode)): \(snippet)"
            case .cancelled:
                return "Cancelled"
            case .ioError(let message):
                return "I/O error: \(message)"
            case .notImplemented(let reason):
                return "Not implemented: \(reason)"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Internal hooks (tests + Wave 3)

    /// Update the running average given a freshly completed item duration.
    /// Exposed `internal` so Wave 3 engine loop + tests can drive it
    /// deterministically without spinning up real engines.
    func recordCompletion(duration: TimeInterval) {
        let n = items.filter { $0.state == .done }.count
        guard n > 0 else {
            averageDuration = duration
            return
        }
        if let avg = averageDuration {
            // Incremental running average — n already includes the just-completed item.
            averageDuration = avg + (duration - avg) / Double(n)
        } else {
            averageDuration = duration
        }
    }

    /// Test-only setter for `phase` to drive state transitions in isolation
    /// from the (Wave 2/3) preflight + engine wiring.
    func setPhaseForTesting(_ newPhase: Phase) {
        phase = newPhase
    }

    /// Apply a freshly-decoded thumbnail blob to the item with `id`. No-op if
    /// the item was removed before the background task finished.
    fileprivate func applyThumbnail(id: UUID, data: Data) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].thumbnailData = data
    }

    // MARK: - Thumbnail (background)

    /// Decode a small thumbnail blob from `url` using ImageIO. Returns `nil`
    /// on any failure (unreadable / non-image / decode error) — UI falls back
    /// to the placeholder glyph.
    nonisolated static func makeThumbnailData(for url: URL) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
