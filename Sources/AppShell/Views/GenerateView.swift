import SwiftUI
import AppKit
import ImagingCore

/// Generate section — prompt input + sliders + result preview + 3 actions
/// (Save As / Send to Upscale / Edit). Renders when MainView's segmented
/// control is set to .generate.
///
/// v0.4.0.0 ships with the SDXL model not yet downloaded — the "Üret"
/// button surfaces a clear prompt to install the model from Settings.
/// Real generation arrives in v0.4.0.1.
@MainActor
struct GenerateView: View {
    @State private var viewModel = GenerationViewModel()
    @Bindable private var settings = SettingsStore.shared
    @State private var manager = ModelDownloadManager.shared
    @State private var showDownloadSheet: Bool = false

    /// Optional handoff closures provided by the parent (MainView). When
    /// the customer taps "Upscale'e gönder" or "Düzenle", MainView
    /// switches sections and feeds the URL into the appropriate flow.
    let onSendToUpscale: (URL) -> Void
    let onSendToEditor: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                modelStatusBanner

                promptInputs

                paramRow

                actionRow

                resultArea
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showDownloadSheet) {
            ModelDownloadProgressView(isPresented: $showDownloadSheet)
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var modelStatusBanner: some View {
        if !settings.sdModelAvailable {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.down.circle.dotted")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("SDXL modeli yüklü değil")
                        .font(.callout.weight(.semibold))
                    Text("Görüntü oluşturma için Apple Core ML SDXL bundle'ı (~6.7 GB) indirilmeli. İndirme bir kez yapılır, sonraki açılışlarda gerek yok.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    showDownloadSheet = true
                    Task { await manager.startDownload() }
                } label: {
                    Label("İndir", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(8)
        }
    }

    // MARK: - Prompt inputs

    private var promptInputs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.callout.weight(.semibold))
            TextEditor(text: $viewModel.prompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 110)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            DisclosureGroup("Negatif prompt") {
                TextEditor(text: $viewModel.negativePrompt)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 50, maxHeight: 80)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .font(.caption)
        }
    }

    // MARK: - Params

    private var paramRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Adım")
                    .font(.callout)
                    .frame(width: 70, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(viewModel.steps) },
                    set: { viewModel.steps = Int($0) }
                ), in: 15...50, step: 1)
                Text("\(viewModel.steps)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Text("CFG")
                    .font(.callout)
                    .frame(width: 70, alignment: .leading)
                Slider(value: $viewModel.cfgScale, in: 5...15, step: 0.5)
                Text(String(format: "%.1f", viewModel.cfgScale))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            HStack(spacing: 12) {
                Text("Boyut")
                    .font(.callout)
                    .frame(width: 70, alignment: .leading)
                Picker("", selection: sizeBinding) {
                    // Iterate by index to avoid an id collision when two sizes
                    // share a width (1024×1024 vs 1024×1536). v0.4.1.3 bug
                    // surfaced as "Kare S | Kare M | Kare M | Yatay" because
                    // ForEach(_, id: \.0) keyed on width alone.
                    ForEach(Array(GenerationDefaults.supportedSizes.enumerated()),
                            id: \.offset) { _, pair in
                        let (w, h) = pair
                        Text(GenerationDefaults.shortSizeLabel(width: w, height: h))
                            .tag(GenerationDefaults.sizeTag(width: w, height: h))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Kare S 768×768 · Kare M 1024×1024 · Dikey 1024×1536 · Yatay 1536×1024")
            }
            HStack(spacing: 12) {
                Text("Tohum")
                    .font(.callout)
                    .frame(width: 70, alignment: .leading)
                Toggle("Rastgele", isOn: $viewModel.randomSeed)
                    .toggleStyle(.checkbox)
                if !viewModel.randomSeed {
                    TextField("seed", value: $viewModel.seed, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .font(.callout.monospacedDigit())
                }
                Spacer()
            }
        }
    }

    private var sizeBinding: Binding<String> {
        Binding(
            get: { "\(viewModel.width)x\(viewModel.height)" },
            set: { raw in
                let parts = raw.split(separator: "x").compactMap { Int($0) }
                if parts.count == 2 {
                    viewModel.width = parts[0]
                    viewModel.height = parts[1]
                }
            }
        )
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 12) {
            if viewModel.isRunning {
                Button("İptal", role: .cancel) {
                    viewModel.cancel()
                }
            } else {
                Button {
                    viewModel.start()
                } label: {
                    Label("Üret", systemImage: "sparkles")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!settings.sdModelAvailable || viewModel.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
    }

    // MARK: - Result area

    @ViewBuilder
    private var resultArea: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Model belleğe yükleniyor…")
                        .font(.callout)
                }
                Text("İlk üretim için 30 sn - 2 dk arası beklemeyi göze al (Core ML model warm-up). Sonraki üretimler hızlı olacak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .running(let step, let total):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(step), total: Double(total))
                Text("Üretiliyor — \(step) / \(total) adım")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed(let url, let seed):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(url.lastPathComponent)
                        .font(.caption)
                    Spacer()
                    Text("seed: \(seed)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                        .cornerRadius(6)
                }
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    Button {
                        onSendToUpscale(url)
                    } label: {
                        Label("Upscale'e gönder", systemImage: "arrow.up.right.square")
                    }
                    Button {
                        onSendToEditor(url)
                    } label: {
                        Label("Düzenle", systemImage: "pencil.tip.crop.circle")
                    }
                    Spacer()
                }
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
