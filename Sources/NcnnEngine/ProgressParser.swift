import Foundation

/// Parses ncnn-vulkan stderr lines like "12.50%" and emits 0.0-1.0 progress.
/// Stateful — handles chunked input where a percentage may straddle a buffer boundary.
public final class ProgressParser {
    private let onProgress: @Sendable (Double) -> Void
    private var buffer = ""

    public init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    /// Feed any string chunk (typically from a `Pipe` read). Splits on newline,
    /// parses each complete line, retains an incomplete trailing fragment.
    public func feed(_ chunk: String) {
        buffer += chunk
        while let newlineIdx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newlineIdx])
            buffer.removeSubrange(buffer.startIndex...newlineIdx)
            parseLine(line)
        }
    }

    /// Force-parse any trailing buffered content (e.g. on stream close).
    public func flush() {
        if !buffer.isEmpty {
            parseLine(buffer)
            buffer = ""
        }
    }

    // MARK: - Private

    private func parseLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.hasSuffix("%") else { return }
        let numericPart = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
        guard let percent = Double(numericPart) else { return }
        let clamped = min(max(percent, 0.0), 100.0)
        onProgress(clamped / 100.0)
    }
}
