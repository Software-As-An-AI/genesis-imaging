import SwiftUI
import ImagingCore

// MARK: - PerItemOverridePopover

/// Popover surfaced from a `QueueRowView`'s gear button. Lets the operator
/// override the batch defaults for a single item (or reset back to "use
/// batch default"). Bindings flow through `BatchQueue.setOverride(...)` so
/// the row reactively reflects the change as soon as the popover closes.
///
/// UX shape: two Pickers (Model + Scale) + Apply / Reset actions. Apply
/// commits the local selection to the queue; Reset clears both overrides.
@MainActor
public struct PerItemOverridePopover: View {
    @ObservedObject var queue: BatchQueue
    let itemID: UUID

    /// Dismiss callback supplied by parent. Wave 2: parent owns popover state.
    var onDismiss: () -> Void

    /// Local edit state — only flushed to `BatchQueue` on "Uygula". `nil`
    /// represents "use batch default" (matches `QueueItem.modelOverride` /
    /// `QueueItem.scaleOverride`).
    @State private var selectedModel: String?
    @State private var selectedScale: Int?

    public init(
        queue: BatchQueue,
        itemID: UUID,
        onDismiss: @escaping () -> Void
    ) {
        self.queue = queue
        self.itemID = itemID
        self.onDismiss = onDismiss
    }

    /// Models surfaced in the picker. Matches `MainView.supportedModels` —
    /// keep in sync if the engines grow new models.
    private var supportedModels: [String] {
        [
            "realesrgan-x4plus",
            "realesrgan-x4plus-anime",
            "realesr-animevideov3-x4",
            "realesr-animevideov3-x3",
            "realesr-animevideov3-x2",
        ]
    }

    private let supportedScales: [Int] = [2, 3, 4]

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bu dosya için ayarı değiştir")
                .font(.headline)

            Divider()

            // Model picker — "Batch varsayılanı" === selectedModel == nil.
            HStack {
                Text("Model")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $selectedModel) {
                    Text("Batch varsayılanı (\(queue.defaultModel))").tag(String?.none)
                    ForEach(supportedModels, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            // Scale picker — "Batch varsayılanı" === selectedScale == nil.
            HStack {
                Text("Ölçek")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $selectedScale) {
                    Text("Batch varsayılanı (x\(queue.defaultScale))").tag(Int?.none)
                    ForEach(supportedScales, id: \.self) { factor in
                        Text("x\(factor)").tag(Int?.some(factor))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            Divider()

            HStack {
                Button("Varsayılana dön") {
                    selectedModel = nil
                    selectedScale = nil
                    queue.setOverride(itemID: itemID, model: nil, scale: nil)
                    onDismiss()
                }
                .controlSize(.small)

                Spacer()

                Button("İptal") {
                    onDismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

                Button("Uygula") {
                    queue.setOverride(
                        itemID: itemID,
                        model: selectedModel,
                        scale: selectedScale
                    )
                    onDismiss()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 360)
        .onAppear {
            // Seed local edit state from the queue item's current overrides.
            if let item = queue.items.first(where: { $0.id == itemID }) {
                selectedModel = item.modelOverride
                selectedScale = item.scaleOverride
            }
        }
    }
}
