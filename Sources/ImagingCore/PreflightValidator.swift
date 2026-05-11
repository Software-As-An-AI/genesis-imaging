import Foundation
import ImageIO
import CoreGraphics

// MARK: - PreflightValidator

/// Pure-function validator that scans a `BatchQueue`'s items + global setup
/// before processing begins. Surfaces 8 issue types so the UI can refuse the
/// run, let the operator remove offending items, or release power-user
/// overrides (per-item or batch-level). Runtime rare errors (mid-engine OOM,
/// IO race) are NOT preflight concerns — they flow through the engine loop's
/// skip+continue path.
///
/// All checks are **read-only** + idempotent. Heavy work (image decode) is
/// done via `ImageIO` to avoid loading pixel data into memory.
public struct PreflightValidator: Sendable {
    /// Extensions the engines support. Lower-cased + extension-only check.
    public static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "webp",
    ]

    /// Conservative safety factor for memory budget: estimated peak working set
    /// must fit under `physicalMemory × safetyFactor`. 0.5 is intentionally
    /// generous (other apps + OS + engine intermediates).
    public static let memorySafetyFactor: Double = 0.5

    /// Disk overhead multiplier — total estimated output bytes are scaled by
    /// this before comparing to free space (account for tmp file during
    /// atomic write + format header overhead).
    public static let diskOverheadFactor: Double = 1.2

    public init() {}

    // MARK: - Public API

    /// Run all checks against `items`. Returns one issue per problem found;
    /// item-level checks short-circuit per item (first issue wins per item),
    /// global checks always run. Order: per-item first (in queue order), then
    /// global (disk, memory, model).
    ///
    /// - Parameters:
    ///   - items: Current queue contents (state ignored — preflight runs in `.draft`).
    ///   - outputDir: Resolved batch override directory; `nil` means "same dir per item".
    ///     If non-nil, parent-dir writability is checked once globally.
    ///   - defaultModel: Batch default model (applies when item has no override).
    ///   - defaultScale: Batch default scale.
    ///   - modelsDirectory: Where to look for `<model>.bin/.param` (Ncnn) or
    ///     `<model>.mlmodelc` (CoreML). Passed in for testability — production
    ///     callers pass `Bundle.main.resourceURL?.appendingPathComponent("Models")`.
    public func validate(
        items: [QueueItem],
        outputDir: URL?,
        defaultModel: String,
        defaultScale: Int,
        modelsDirectory: URL?
    ) async -> [PreflightIssue] {
        var issues: [PreflightIssue] = []

        // Per-item checks (file → decode → format → memory).
        // Memory per-item rather than max — both are valid; per-item lets UI
        // pinpoint the offender.
        for item in items {
            let scale = item.effectiveScale(batchDefault: defaultScale)
            if let perItem = validateItem(item: item, scale: scale) {
                issues.append(perItem)
                continue
            }
        }

        // Global: output dir writability (only if batch override set).
        if let dir = outputDir {
            let parent = dir.standardizedFileURL
            if !FileManager.default.fileExists(atPath: parent.path) ||
               !FileManager.default.isWritableFile(atPath: parent.path) {
                issues.append(.outputNotWritable(parent))
            }
        }

        // Global: disk space estimate.
        if let diskIssue = checkDiskSpace(items: items, defaultScale: defaultScale, outputDir: outputDir) {
            issues.append(diskIssue)
        }

        // Global: model file presence.
        if let modelIssue = checkModelPresence(items: items,
                                               defaultModel: defaultModel,
                                               modelsDirectory: modelsDirectory) {
            issues.append(modelIssue)
        }

        return issues
    }

    // MARK: - Per-item

    /// Check a single item; return first issue found (existence → readable →
    /// format → decodable → memory). Returns `nil` if item passes.
    func validateItem(item: QueueItem, scale: Int) -> PreflightIssue? {
        let url = item.sourceURL
        let fm = FileManager.default

        // 1. Existence.
        guard fm.fileExists(atPath: url.path) else {
            return .fileMissing(url)
        }

        // 2. Readable.
        guard fm.isReadableFile(atPath: url.path) else {
            return .unreadable(url)
        }

        // 3. Format whitelist (extension-based).
        let ext = url.pathExtension.lowercased()
        if !Self.supportedExtensions.contains(ext) {
            return .unsupportedFormat(url, ext)
        }

        // 4. Decodable + pixel-count check (single CGImageSource pass).
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .undecodable(url)
        }
        guard CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return .undecodable(url)
        }
        let pixelWidth = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let pixelHeight = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else {
            return .undecodable(url)
        }

        // 5. Memory budget: input pixels × scale² × 4 bytes (RGBA) < phys × safety.
        let estimatedBytes = Int64(pixelWidth) * Int64(pixelHeight)
            * Int64(scale * scale) * 4
        let budgetBytes = Int64(Double(ProcessInfo.processInfo.physicalMemory)
                                * Self.memorySafetyFactor)
        if estimatedBytes > budgetBytes {
            let estMB = Int(estimatedBytes / (1024 * 1024))
            return .memoryRisk(url, estimatedMB: estMB)
        }

        return nil
    }

    // MARK: - Global

    /// Sum input file sizes × scale² and compare to free space on the target
    /// volume. `nil` if comfortable, `.diskSpaceInsufficient(needed:available:)`
    /// if not.
    func checkDiskSpace(items: [QueueItem], defaultScale: Int, outputDir: URL?) -> PreflightIssue? {
        var estimatedTotal: Int64 = 0
        for item in items {
            let scale = item.effectiveScale(batchDefault: defaultScale)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: item.sourceURL.path)[.size] as? Int64) ?? 0
            // Output bytes ≈ input bytes × scale² (lossy approximation — actual
            // PNG output may compress better/worse, this is conservative for
            // typical natural images).
            estimatedTotal += bytes * Int64(scale * scale)
        }
        estimatedTotal = Int64(Double(estimatedTotal) * Self.diskOverheadFactor)

        // Volume: outputDir if set, else parent of first item.
        let probeURL = outputDir ?? items.first?.sourceURL.deletingLastPathComponent()
        guard let probe = probeURL else { return nil }

        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: probe.path),
              let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value
        else {
            // No reading → cannot prove insufficient → no issue surfaced.
            return nil
        }
        if estimatedTotal > free {
            return .diskSpaceInsufficient(needed: estimatedTotal, available: free)
        }
        return nil
    }

    /// Verify all referenced models (batch default + per-item overrides) exist
    /// in `modelsDirectory`. Returns the first missing model name (or `nil`).
    ///
    /// Model presence convention:
    /// - Ncnn: `<dir>/<model>.bin` AND `<dir>/<model>.param`
    /// - CoreML: `<dir>/<model>.mlmodelc`
    ///
    /// We accept *any* of these — the engine factory chooses at runtime.
    func checkModelPresence(items: [QueueItem],
                            defaultModel: String,
                            modelsDirectory: URL?) -> PreflightIssue? {
        guard let dir = modelsDirectory else {
            // Nothing to verify against. Treat as soft-pass (Bundle resolution
            // may happen at engine init time; surfacing as preflight noise hurts UX).
            return nil
        }

        let names = Set([defaultModel] + items.compactMap { $0.modelOverride })
        for name in names {
            let ncnnBin = dir.appendingPathComponent("\(name).bin")
            let ncnnParam = dir.appendingPathComponent("\(name).param")
            let coreml = dir.appendingPathComponent("\(name).mlmodelc")
            let fm = FileManager.default
            let ncnnPresent = fm.fileExists(atPath: ncnnBin.path)
                && fm.fileExists(atPath: ncnnParam.path)
            let coremlPresent = fm.fileExists(atPath: coreml.path)
            if !ncnnPresent && !coremlPresent {
                return .modelMissing(name)
            }
        }
        return nil
    }
}
