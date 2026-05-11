import Foundation

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
/// Engine-agnostic: knows nothing about NCNN vs CoreML. Wave 2/3 will wire
/// `preflight()` to `PreflightValidator` and `start()` to `OutputWriter` +
/// the engine factory in `AppShell`.
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
    public func add(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let existing = Set(items.map { $0.sourceURL.standardizedFileURL })
        var seenInBatch: Set<URL> = []
        for url in urls {
            let key = url.standardizedFileURL
            if existing.contains(key) || seenInBatch.contains(key) { continue }
            seenInBatch.insert(key)
            items.append(QueueItem(sourceURL: url))
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

    // MARK: - Lifecycle (Wave 2/3 wiring)

    /// Run pre-flight validation against current `items`. Wave 1: stub returns
    /// `preflightIssues` as-is so tests can drive the state machine directly.
    /// Wave 2 will wire `PreflightValidator.validate(...)`.
    public func preflight() async -> [PreflightIssue] {
        phase = .validating
        // Wave 2 wiring point — for now we preserve any pre-populated issues
        // (tests can inject directly via `preflightIssues`).
        let issues = preflightIssues
        phase = issues.isEmpty ? .ready : .draft
        return issues
    }

    /// Begin sequential processing. Wave 1: stub flips phase to `.processing`
    /// so transition tests can run; Wave 3 will iterate items through the
    /// engine + `OutputWriter`.
    public func start() async {
        guard phase == .ready || phase == .draft else { return }
        phase = .processing
        startTime = Date()
        // Wave 3 wiring point.
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
}
