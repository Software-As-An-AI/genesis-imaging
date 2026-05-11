import SwiftUI
import ImagingCore

// MARK: - PreflightIssuesView

/// Banner shown above the batch queue when `PreflightValidator` surfaced one
/// or more issues. Each row renders a human-readable Turkish message + a
/// "Listeden çıkar" affordance when the issue is tied to a specific item URL.
/// Global issues (disk space, model missing) show only the message.
///
/// Wave 2: pure presentation + remove callback. Wave 3 wires
/// `BatchQueue.preflight()` invocation + re-validation after removals.
@MainActor
public struct PreflightIssuesView: View {
    @ObservedObject var queue: BatchQueue

    public init(queue: BatchQueue) {
        self.queue = queue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Hazırlık kontrolü sorunları (\(queue.preflightIssues.count))")
                    .font(.headline)
                Spacer()
                Button("Tümünü çıkar") {
                    removeAllAffected()
                }
                .controlSize(.small)
                .disabled(itemURLsFromIssues().isEmpty)
            }

            Divider()

            ForEach(Array(queue.preflightIssues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                    Text(message(for: issue))
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if let url = issueURL(issue),
                       let itemID = queue.items.first(where: { $0.sourceURL == url })?.id {
                        Button("Listeden çıkar") {
                            queue.remove(itemID: itemID)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    // MARK: - Helpers

    /// Human-readable Turkish message for each `PreflightIssue` case.
    private func message(for issue: PreflightIssue) -> String {
        switch issue {
        case .fileMissing(let url):
            return "Dosya bulunamadı: `\(url.lastPathComponent)`"
        case .unreadable(let url):
            return "Okunamıyor: `\(url.lastPathComponent)`"
        case .undecodable(let url):
            return "Görüntü çözülemiyor (bozuk olabilir): `\(url.lastPathComponent)`"
        case .unsupportedFormat(let url, let ext):
            return "Desteklenmeyen format `.\(ext)`: `\(url.lastPathComponent)`"
        case .outputNotWritable(let url):
            return "Yazma izni yok: `\(url.lastPathComponent)`"
        case .diskSpaceInsufficient(let needed, let available):
            let neededMB = needed / (1024 * 1024)
            let availableMB = available / (1024 * 1024)
            return "Disk alanı yetersiz (gerekli: \(neededMB) MB, mevcut: \(availableMB) MB)"
        case .memoryRisk(let url, let mb):
            return "Bellek riski: `\(url.lastPathComponent)` (~\(mb) MB)"
        case .modelMissing(let name):
            return "Model dosyası eksik: `\(name)`"
        }
    }

    /// URL associated with an issue, if any (global issues return `nil`).
    private func issueURL(_ issue: PreflightIssue) -> URL? {
        switch issue {
        case .fileMissing(let url),
             .unreadable(let url),
             .undecodable(let url),
             .outputNotWritable(let url):
            return url
        case .unsupportedFormat(let url, _),
             .memoryRisk(let url, _):
            return url
        case .diskSpaceInsufficient, .modelMissing:
            return nil
        }
    }

    /// All distinct item URLs referenced by current issues — used by the
    /// "Tümünü çıkar" affordance.
    private func itemURLsFromIssues() -> Set<URL> {
        Set(queue.preflightIssues.compactMap { issueURL($0) })
    }

    /// Remove every queue item whose URL appears in any issue. Global issues
    /// (which have no URL) are left for the operator to address separately.
    private func removeAllAffected() {
        let urls = itemURLsFromIssues()
        let affectedIDs = queue.items
            .filter { urls.contains($0.sourceURL) }
            .map { $0.id }
        for id in affectedIDs {
            queue.remove(itemID: id)
        }
    }
}
