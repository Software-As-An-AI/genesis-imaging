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

    /// In-flight eraser session, if the editor sheet is presented for this
    /// row. Local to the row — only one eraser sheet per row at a time.
    @State private var eraserSession: EraserSession? = nil
    @State private var eraserLoadError: String? = nil

    public init(
        queue: BatchQueue,
        item: QueueItem,
        openOverridePopoverID: Binding<UUID?>
    ) {
        self.queue = queue
        self.item = item
        self._openOverridePopoverID = openOverridePopoverID
    }

    /// Decode the output PNG and present the eraser sheet. Errors surface
    /// as a brief alert; the row stays unchanged on failure.
    private func presentEraserSheet(for url: URL) {
        do {
            eraserSession = try EraserSession.load(from: url)
        } catch {
            eraserLoadError = "Düzenleyici açılamadı: \(error.localizedDescription)"
        }
    }

    /// Edit is offered when the item has a stable file to edit: either the
    /// completed output, or the pre-upscale source. Mid-run states get no
    /// edit button (the file is being written to).
    private var editAvailable: Bool {
        switch item.state {
        case .done:    return item.outputURL != nil
        case .pending: return true
        case .processing, .failed, .skipped: return false
        }
    }

    /// Edit target: prefer the upscaled output if available; otherwise the
    /// source. Customer can clean up either side of the upscale step.
    private var editTargetURL: URL {
        item.outputURL ?? item.sourceURL
    }

    private var editTooltip: String {
        if item.outputURL != nil {
            return "Düzenle — silgi (upscale çıktısı)"
        }
        return "Düzenle — silgi (upscale öncesi kaynak)"
    }

    public var body: some View {
        HStack(spacing: 12) {
            thumbnailButton
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

            if item.state == .done, let outURL = item.outputURL {
                Button {
                    NSWorkspace.shared.open(outURL)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.iconHover)
                .help("Önizleme'de aç")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.iconHover)
                .help("Finder'da göster")
            }

            // Edit button — available from the moment a source exists in
            // the queue (pending OR done). Lets the customer clean up
            // unwanted detail BEFORE the long upscale run, or revisit
            // editing on the output after upscale. Disabled only mid-run
            // (processing/failed states make in-place edits risky).
            if editAvailable {
                Button {
                    presentEraserSheet(for: editTargetURL)
                } label: {
                    Image(systemName: "pencil.tip.crop.circle")
                }
                .buttonStyle(.iconHover)
                .help(editTooltip)
            }

            Button {
                openOverridePopoverID = item.id
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.iconHover)
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
            .buttonStyle(.iconHover)
            .help("Listeden çıkar")
            .disabled(queue.phase == .processing && item.state == .processing)
        }
        .padding(.vertical, 6)
        .sheet(item: Binding(
            get: { eraserSession.map { EraserSessionWrapper(id: item.id, session: $0) } },
            set: { newValue in if newValue == nil { eraserSession = nil } }
        )) { wrapper in
            EraserEditorView(
                session: wrapper.session,
                onSaved: { _ in eraserSession = nil },
                onCancel: { eraserSession = nil }
            )
        }
        .alert("Eraser açılamadı", isPresented: Binding(
            get: { eraserLoadError != nil },
            set: { if !$0 { eraserLoadError = nil } }
        )) {
            Button("Tamam", role: .cancel) { eraserLoadError = nil }
        } message: {
            Text(eraserLoadError ?? "")
        }
    }

    /// SwiftUI `.sheet(item:)` needs `Identifiable`. `EraserSession` is a
    /// class but not Identifiable; wrap it so the row's item id drives
    /// dismissal semantics.
    private struct EraserSessionWrapper: Identifiable {
        let id: UUID
        let session: EraserSession
    }

    // MARK: - Subviews

    /// Thumbnail wrapped in a borderless button. When the item is `.done`
    /// and has a resolved `outputURL`, tapping triggers Quick Look on the
    /// upscaled file (native macOS preview overlay, same as space-bar in
    /// Finder). Otherwise the button is non-interactive so the row's natural
    /// drag/hover still feels right.
    @ViewBuilder
    private var thumbnailButton: some View {
        if item.state == .done, let outURL = item.outputURL {
            HoverableThumbnail(outURL: outURL) {
                thumbnail
            }
            .help("Önizleme (Quick Look)")
        } else {
            thumbnail
        }
    }

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

    /// Wraps the thumbnail in a hover-aware Button that highlights an accent
    /// border + slight scale lift on mouse-over, signaling that clicking
    /// will open Quick Look.
    private struct HoverableThumbnail<Content: View>: View {
        let outURL: URL
        let content: () -> Content
        @State private var isHovered = false

        init(outURL: URL, @ViewBuilder content: @escaping () -> Content) {
            self.outURL = outURL
            self.content = content
        }

        var body: some View {
            Button {
                QuickLookCoordinator.shared.preview(outURL)
            } label: {
                content()
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isHovered ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .scaleEffect(isHovered ? 1.03 : 1.0)
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
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
