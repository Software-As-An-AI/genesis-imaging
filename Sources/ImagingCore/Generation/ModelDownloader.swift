import Foundation

/// Low-level URLSession orchestrator for a single SDXL bundle download.
///
/// Owns the `URLSession` + delegate plumbing; emits progress + lifecycle
/// events through a closure provided by `ModelDownloadManager`. Designed as
/// a fresh-per-attempt instance — manager creates one, holds it for the
/// download lifetime, drops it on completion/cancellation.
///
/// Resumable: persists `resumeData` to UserDefaults on session-level error;
/// `resume()` picks up where it left off. Cancel clears resume state so the
/// next attempt starts fresh from the operator's perspective.
///
/// ETA: rolling 10-second throughput window, capped at 99 minutes display.
public final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    public enum Event: Sendable {
        case progress(bytesWritten: Int64, totalBytes: Int64, throughputBytesPerSec: Double?, etaSeconds: Int?)
        case finished(localTempURL: URL)
        case cancelled
        case failed(message: String)
    }

    public typealias EventCallback = @Sendable (Event) -> Void

    private let url: URL
    private let resumeKey: String
    private let callback: EventCallback
    private var session: URLSession!
    private var task: URLSessionDownloadTask?

    // Throughput window: timestamped (bytes-delta) samples within last 10s.
    private var samples: [(timestamp: Date, totalBytes: Int64)] = []
    private let throughputWindowSeconds: TimeInterval = 10
    private var lastEmitAt: Date = .distantPast
    private let emitMinInterval: TimeInterval = 0.1 // 10 Hz throttle

    private let lock = NSLock()

    /// - Parameters:
    ///   - url: source download URL (typically `SDXLModelCatalog.Variant.downloadURL`)
    ///   - resumeKey: UserDefaults key for resumeData persistence
    ///   - callback: invoked with progress + lifecycle events. Called on
    ///     URLSession's delegate queue (background) — caller responsible for
    ///     dispatching to MainActor if UI binding is needed.
    public init(url: URL, resumeKey: String = "imaging.sdxl.resumeData", callback: @escaping EventCallback) {
        self.url = url
        self.resumeKey = resumeKey
        self.callback = callback
        super.init()
        let config = URLSessionConfiguration.default
        // Allow background continuation when window inactive; large downloads
        // on slow links benefit. Not the iOS-style background session — just
        // foreground tolerance.
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 4 // 4h cap for very slow links
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        if task != nil { return }
        if let data = UserDefaults.standard.data(forKey: resumeKey) {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: url)
        }
        samples.removeAll(keepingCapacity: true)
        task?.resume()
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        task?.cancel(byProducingResumeData: { [weak self] data in
            // Per UX: explicit cancel = throw away resume state. Network-level
            // errors keep resumeData (that path is in `didCompleteWithError`).
            _ = data
            self?.clearResumeData()
        })
        task = nil
        callback(.cancelled)
    }

    /// Called by manager when the post-download verify/extract pipeline ate
    /// the file. Cleans up resume state on success so the next download starts
    /// fresh, not from stale resumeData. (Avoid the name `finalize` — NSObject
    /// reserves it for deinit-time finalization.)
    public func cleanup() {
        clearResumeData()
        session.invalidateAndCancel()
    }

    private func clearResumeData() {
        UserDefaults.standard.removeObject(forKey: resumeKey)
    }

    // MARK: - URLSessionDownloadDelegate

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        lock.lock()
        let now = Date()
        samples.append((now, totalBytesWritten))
        // Drop samples older than window
        let cutoff = now.addingTimeInterval(-throughputWindowSeconds)
        samples.removeAll { $0.timestamp < cutoff }

        // Throttle UI emits
        let shouldEmit = now.timeIntervalSince(lastEmitAt) >= emitMinInterval
            || totalBytesWritten == totalBytesExpectedToWrite
        if shouldEmit { lastEmitAt = now }
        let copy = samples
        lock.unlock()

        guard shouldEmit else { return }

        let throughput: Double? = {
            guard let first = copy.first, let last = copy.last, last.timestamp > first.timestamp else { return nil }
            let dt = last.timestamp.timeIntervalSince(first.timestamp)
            let db = Double(last.totalBytes - first.totalBytes)
            return db / dt
        }()
        let eta: Int? = {
            guard let bps = throughput, bps > 0, totalBytesExpectedToWrite > 0 else { return nil }
            let remaining = Double(totalBytesExpectedToWrite - totalBytesWritten)
            return min(99 * 60, Int(remaining / bps))
        }()
        callback(.progress(bytesWritten: totalBytesWritten,
                           totalBytes: totalBytesExpectedToWrite,
                           throughputBytesPerSec: throughput,
                           etaSeconds: eta))
    }

    public func urlSession(_ session: URLSession,
                           downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        // URLSession deletes the temp file at `location` shortly after this
        // callback returns. Move it into our cache dir immediately to keep
        // the verify+unzip pipeline (Step 3) from racing the cleanup.
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenesisImaging-sdxl-staging", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let dest = cacheDir.appendingPathComponent("sdxl-bundle.zip")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            callback(.finished(localTempURL: dest))
        } catch {
            callback(.failed(message: "Move staging file failed: \(error.localizedDescription)"))
        }
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        guard let error else { return } // success path handled above
        let nsErr = error as NSError
        // Persist resumeData on transient network failure so the next start()
        // resumes. Explicit user-cancel hits `cancel()` first, which clears it.
        if let data = nsErr.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            UserDefaults.standard.set(data, forKey: resumeKey)
        }
        if nsErr.code == NSURLErrorCancelled {
            // Already handled in cancel()
            return
        }
        callback(.failed(message: nsErr.localizedDescription))
    }
}
