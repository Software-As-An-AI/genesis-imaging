import SwiftUI
import AppKit
import ImagingCore

// MARK: - QueueRowView

/// Single row inside `BatchQueueView`'s list. Renders the thumbnail (decoded
/// lazily from `QueueItem.thumbnailData`), filename (truncate-middle), a
/// state icon, an inline per-row progress bar (visible only while the item
/// is processing), and two action affordances: gear (⚙) to open the
/// per-item override popover, and remove (✕).
///
/// Wave 2: pure presentation + queue-mutating callbacks. Wave 3 will keep
/// the row in sync with engine-driven progress updates and surface error
/// messages on hover.
@MainActor
public struct QueueRowView: View {
    @ObservedObject var queue: BatchQueue
    let item: QueueItem

    /// Tracks which item has its override popover open. Owned by the parent
    /// list so only one popover is visible at a time.
    @Binding var openOverridePopoverID: UUID?

    public init(
        queue: BatchQueue,
        item: QueueItem,
        openOverridePopoverID: Binding<UUID?>
    ) {
        self.queue = queue
        self.item = item
        self._openOverridePopoverID = openOverridePopoverID
    }

    public var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 64, height: 64)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    stateIcon
                    Text(item.sourceURL.lastPathComponent)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                overrideSummary

                if item.state == .processing {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer()

            if let message = item.errorMessage, item.state == .failed {
                // Hover tooltip surfaces the engine error for triage without
                // bloating the row.
                Image(systemName: "info.circle")
                    .foregroundStyle(.orange)
                    .help(message)
            }

            Button {
                openOverridePopoverID = item.id
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Bu dosya için model/ölçek ayarı")
            .popover(
                isPresented: Binding(
                    get: { openOverridePopoverID == item.id },
                    set: { isOpen in
                        if !isOpen { openOverridePopoverID = nil }
                    }
                ),
                arrowEdge: .leading
            ) {
                PerItemOverridePopover(
                    queue: queue,
                    itemID: item.id,
                    onDismiss: { openOverridePopoverID = nil }
                )
            }

            Button {
                queue.remove(itemID: item.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Listeden çıkar")
            .disabled(queue.phase == .processing && item.state == .processing)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Subviews

    /// Decoded `NSImage` from `thumbnailData` if present, else a placeholder
    /// glyph. Decoding is cheap (64×64) and happens per-render — Wave 3 may
    /// cache via `@State` if scroll latency surfaces.
    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.thumbnailData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipped()
                .cornerRadius(6)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
        }
    }

    /// SF Symbol mapped to `QueueItemState`. Color encodes severity.
    @ViewBuilder
    private var stateIcon: some View {
        switch item.state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .help("Bekliyor")
        case .processing:
            Image(systemName: "arrow.2.circlepath")
                .foregroundStyle(Color.accentColor)
                .help("İşleniyor")
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Tamamlandı")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Hata")
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .help("Atlandı")
        }
    }

    /// Small caption surfacing per-item overrides (or duration once
    /// completed). Empty otherwise to keep the row compact.
    @ViewBuilder
    private var overrideSummary: some View {
        let model = item.modelOverride
        let scale = item.scaleOverride
        let duration = item.duration

        if let duration = duration, item.state == .done {
            Text(String(format: "%.1fs", duration))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if model != nil || scale != nil {
            HStack(spacing: 6) {
                if let model = model {
                    Text("model: \(model)")
                }
                if let scale = scale {
                    Text("ölçek: x\(scale)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}
