import Foundation

// MARK: - HistoryEntry

/// A single completed upscale operation, persisted for the History view.
public struct HistoryEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let inputPath: String
    public let outputPath: String
    public let modelName: String
    public let scale: Int
    public let inputBytes: Int
    public let outputBytes: Int
    public let durationMs: Int
    public let engineName: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        inputPath: String,
        outputPath: String,
        modelName: String,
        scale: Int,
        inputBytes: Int,
        outputBytes: Int,
        durationMs: Int,
        engineName: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.modelName = modelName
        self.scale = scale
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
        self.durationMs = durationMs
        self.engineName = engineName
    }
}

// MARK: - HistoryStore

/// JSON-file backed history persistence. Engine-agnostic.
///
/// Default location: `~/Library/Application Support/GenesisImaging/history.json`
/// Format: pretty-printed JSON array of `HistoryEntry`, ISO8601 dates.
/// Cap: most-recent `maxEntries` (default 50); older entries pruned on append.
public final class HistoryStore: @unchecked Sendable {
    public static let shared = HistoryStore()

    private let fileURL: URL
    private let maxEntries: Int
    private let queue = DispatchQueue(label: "genesis.history-store", qos: .utility)

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(fileURL: URL? = nil, maxEntries: Int = 50) {
        self.maxEntries = maxEntries
        if let url = fileURL {
            self.fileURL = url
        } else {
            self.fileURL = Self.defaultFileURL()
        }
        ensureDirectoryExists()
    }

    // MARK: - Public API

    /// Append `entry` and prune to `maxEntries` (newest kept).
    public func append(_ entry: HistoryEntry) {
        queue.sync {
            var entries = readEntries()
            entries.append(entry)
            // Sort newest-first so prune keeps the most recent.
            entries.sort { $0.timestamp > $1.timestamp }
            if entries.count > maxEntries {
                entries = Array(entries.prefix(maxEntries))
            }
            writeEntries(entries)
        }
    }

    /// All entries, newest first.
    public func list() -> [HistoryEntry] {
        queue.sync {
            readEntries().sorted { $0.timestamp > $1.timestamp }
        }
    }

    /// Erase all stored entries.
    public func clear() {
        queue.sync {
            writeEntries([])
        }
    }

    // MARK: - Internals

    private static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("GenesisImaging", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    private func ensureDirectoryExists() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func readEntries() -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func writeEntries(_ entries: [HistoryEntry]) {
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
