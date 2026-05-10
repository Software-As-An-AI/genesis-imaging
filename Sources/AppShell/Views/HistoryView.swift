import SwiftUI
import AppKit
import ImagingCore

public struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()
    @State private var showClearConfirm = false

    public init() {}

    public var body: some View {
        Group {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                List(viewModel.entries) { entry in
                    HistoryRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Geçmiş")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Geçmişi temizle", systemImage: "trash")
                }
                .disabled(viewModel.entries.isEmpty)

                Button {
                    viewModel.reload()
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
            }
        }
        .confirmationDialog(
            "Tüm geçmiş silinsin mi?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) { viewModel.clear() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bu işlem geri alınamaz.")
        }
        .onAppear { viewModel.reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("Henüz hiçbir işlem yapılmadı")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Bir resim yükseltince burada görüneceksin.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(filename)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(entry.modelName) \(entry.scale)×")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(timestampText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var thumbnail: some View {
        Group {
            if let img = NSImage(contentsOf: URL(fileURLWithPath: entry.outputPath)) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    )
            }
        }
    }

    private var filename: String {
        (entry.inputPath as NSString).lastPathComponent
    }

    private var timestampText: String {
        let interval = Date().timeIntervalSince(entry.timestamp)
        if interval < 86_400 { // < 24h
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: entry.timestamp, relativeTo: Date())
        } else {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: entry.timestamp)
        }
    }

    private var durationText: String {
        let seconds = Double(entry.durationMs) / 1000.0
        return String(format: "%.1fs", seconds)
    }
}
