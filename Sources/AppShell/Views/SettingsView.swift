import SwiftUI
import ImagingCore

@MainActor
public struct SettingsView: View {
    @Bindable private var settings = SettingsStore.shared
    @State private var showDownloadSheet: Bool = false

    private let modelOptions = [
        "realesrgan-x4plus",
        "realesrgan-x4plus-anime",
        "realesr-animevideov3-x4",
    ]

    private let scaleOptions = [2, 3, 4]

    public init() {}

    public var body: some View {
        Form {
            Section("Motor (Engine)") {
                Picker("Tercih edilen motor", selection: $settings.enginePreference) {
                    Text("Otomatik (önerilen) — Core ML").tag("auto")
                    Text("Core ML (Apple Neural Engine)").tag("coreml")
                    Text("ncnn-vulkan (Metal GPU, Faz 1)").tag("ncnn")
                }
                .pickerStyle(.menu)

                Text(engineHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Varsayılanlar") {
                Picker("Varsayılan model", selection: $settings.defaultModel) {
                    ForEach(modelOptions, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)

                Picker("Varsayılan ölçek", selection: $settings.defaultScale) {
                    ForEach(scaleOptions, id: \.self) { scale in
                        Text("\(scale)×").tag(scale)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Tile size")
                    Spacer()
                    Stepper(
                        value: $settings.defaultTileSize,
                        in: 0...1024,
                        step: 32
                    ) {
                        Text(settings.defaultTileSize == 0
                             ? "auto"
                             : "\(settings.defaultTileSize) px")
                            .monospacedDigit()
                            .frame(minWidth: 70, alignment: .trailing)
                    }
                }
            }

            Section("Smart Output (Sıkıştırma)") {
                // Tek consolide picker — 8 mode tek menüde. Smart Auto
                // default + en üstte. Hint + filename preview seçime göre
                // dinamik güncellenir.
                Picker("Mod", selection: $settings.smartOutputMode) {
                    ForEach(SmartOutputMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text(settings.smartOutputMode.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.smartOutputMode != .off {
                    Text("Çıktı dosya adı: ...-upscaled-\(settings.smartOutputMode.filenameTag ?? "").png")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                if settings.smartOutputMode == .adaptive {
                    Text("Smart Auto içeriğe göre alt-mode seçer; dosya adının sonuna seçilen alt-mode eklenir (örn. `adaptive-binarize`, `adaptive-lineart`).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Görüntü Oluşturma (Model)") {
                variantPicker
                generationModelStatus

                Picker("Varsayılan adım", selection: $settings.defaultGenerationSteps) {
                    Text("Hızlı (15)").tag(15)
                    Text("Standart (30)").tag(30)
                    Text("Yüksek (50)").tag(50)
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Varsayılan CFG")
                    Spacer()
                    Slider(value: $settings.defaultGenerationCFG, in: 5...15, step: 0.5)
                        .frame(width: 160)
                    Text(String(format: "%.1f", settings.defaultGenerationCFG))
                        .font(.callout.monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                }

                Picker("Varsayılan boyut", selection: $settings.defaultGenerationSize) {
                    ForEach(GenerationDefaults.supportedSizes, id: \.0) { (w, h) in
                        Text(GenerationDefaults.longSizeLabel(width: w, height: h))
                            .tag(GenerationDefaults.sizeTag(width: w, height: h))
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Hakkında") {
                LabeledContent("Uygulama", value: "Genesis Imaging")
                LabeledContent("Sürüm", value: appVersion)
                LabeledContent("Açıklama", value: "On-device image creation + enhancement — Apple Silicon native")
                LabeledContent("ncnn binary", value: ncnnBinaryVersion)
            }

            Section("Lisanslar / Third-Party") {
                Text("Genesis Imaging is built on the following open-source / third-party model assets:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Apple ml-stable-diffusion") { Text("MIT License").font(.caption.monospaced()) }
                LabeledContent("SDXL Base Palettized (Apple)") { Text("OpenRAIL++").font(.caption.monospaced()) }
                LabeledContent("ColoringBookRedmond-V2 LoRA") { Text("OpenRAIL-M (artificialguybr)").font(.caption.monospaced()) }
                LabeledContent("FLUX.2 Klein 4B") { Text("Apache 2.0 (Black Forest Labs)").font(.caption.monospaced()) }
                LabeledContent("Qwen3-4B-MLX-4bit") { Text("Apache 2.0 (Qwen / lmstudio-community)").font(.caption.monospaced()) }
                LabeledContent("mlx-swift") { Text("MIT License (Apple)").font(.caption.monospaced()) }
                LabeledContent("flux-2-swift-mlx") { Text("MIT License (VincentGourbin)").font(.caption.monospaced()) }
                LabeledContent("Real-ESRGAN ncnn") { Text("BSD-3-Clause (xinntao)").font(.caption.monospaced()) }
                LabeledContent("Sparkle") { Text("MIT License").font(.caption.monospaced()) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ayarlar")
        .frame(minWidth: 480, minHeight: 420)
        .sheet(isPresented: $showDownloadSheet) {
            ModelDownloadProgressView(isPresented: $showDownloadSheet)
        }
    }

    private var appVersion: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? "0.1.0 (Faz 1)"
    }

    private var ncnnBinaryVersion: String {
        // Faz 1 placeholder — real version surfaced via NcnnEngine.probe() in Faz 2 wire-up.
        "realesrgan-ncnn-vulkan v0.2.0"
    }

    /// Variant selector — surfaces only `isUserSelectable` variants. Switching
    /// the variant updates SettingsStore.sdxlModelVariant (persisted) and the
    /// status row below auto-updates because ModelDownloadManager's compat
    /// shims resolve to the new selection.
    @ViewBuilder
    private var variantPicker: some View {
        Picker("Model varyantı", selection: Binding(
            get: { settings.sdxlModelVariantTyped },
            set: { settings.sdxlModelVariantTyped = $0 }
        )) {
            ForEach(SDXLModelCatalog.Variant.allCases.filter(\.isUserSelectable),
                    id: \.self) { v in
                Text(v.humanLabel).tag(v)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var generationModelStatus: some View {
        let manager = ModelDownloadManager.shared
        let v = settings.sdxlModelVariantTyped
        switch manager.phase(for: v) {
        case .ready:
            installedRow(manager, variant: v)
        case .downloading(let bytes, let total, let throughput, let eta):
            downloadingRow(bytes: bytes, total: total, throughput: throughput,
                           eta: eta, manager: manager, variant: v)
        case .verifying:
            phaseSpinnerRow(label: "Bütünlük doğrulanıyor (SHA256)…")
        case .extracting:
            phaseSpinnerRow(label: "Model arşivi açılıyor…")
        case .failed(let message):
            failedRow(message: message, manager: manager, variant: v)
        case .idle:
            if manager.isInstalled(for: v) {
                installedRow(manager, variant: v)
            } else {
                idleRow(manager, variant: v)
            }
        }
    }

    @ViewBuilder
    private func installedRow(_ manager: ModelDownloadManager,
                              variant: SDXLModelCatalog.Variant) -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Model yüklü — \(variant.humanLabel)")
                Text(variant.versionMarker)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Kaldır", role: .destructive) {
                manager.uninstall(for: variant)
            }
        }
    }

    @ViewBuilder
    private func idleRow(_ manager: ModelDownloadManager,
                         variant: SDXLModelCatalog.Variant) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.down.circle.dotted")
                    .foregroundStyle(.orange)
                Text("Yüklü değil — \(byteCount(variant.expectedSizeBytes)) indirilecek")
                Spacer()
                Button("İndir") {
                    showDownloadSheet = true
                    Task { await manager.startDownload(for: variant) }
                }
                .buttonStyle(.borderedProminent)
            }
            Text("İlk indirme bir kez yapılır. \(variantHint(for: variant))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func downloadingRow(bytes: Int64, total: Int64, throughput: Double?,
                                eta: Int?, manager: ModelDownloadManager,
                                variant: SDXLModelCatalog.Variant) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let progress = total > 0 ? Double(bytes) / Double(total) : 0
            HStack {
                ProgressView(value: progress)
                Text(String(format: "%.0f%%", progress * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 42, alignment: .trailing)
                Button("İptal", role: .cancel) {
                    manager.cancelDownload(for: variant)
                }
            }
            HStack(spacing: 8) {
                Text(byteCount(bytes) + " / " + byteCount(total))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if let bps = throughput {
                    Text("· " + byteCount(Int64(bps)) + "/s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if let eta = eta {
                    Text("· " + etaLabel(eta))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    private func variantHint(for variant: SDXLModelCatalog.Variant) -> String {
        switch variant {
        case .palettized:
            return "Apple'ın genel-amaçlı SDXL temel modeli — manzara, portre, soyut. Geniş prompt yelpazesi destekler."
        case .loraColoring:
            return "Çocuk boyama kitabı için ince-ayarlanmış — kalın siyah outline, beyaz arka plan, kapalı şekiller. Trigger words otomatik: ColoringBookAF, Coloring Book."
        case .fluxKlein:
            return "FLUX.2 Klein 4B — Apple Silicon MLX framework. Çocuk boyama estetiği için en güçlü; ~35 sn üretim; ~11 GB indirme. Phase A.4 deneysel."
        case .base, .iosSplitEinsum:
            return ""
        }
    }

    @ViewBuilder
    private func phaseSpinnerRow(label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.callout)
        }
    }

    private func byteCount(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    private func etaLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "~\(seconds) sn kaldı" }
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 { return "~\(m) dk kaldı" }
        return "~\(m) dk \(s) sn kaldı"
    }

    @ViewBuilder
    private func failedRow(message: String, manager: ModelDownloadManager,
                           variant: SDXLModelCatalog.Variant) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("İndirme başarısız oldu — \(variant.humanLabel)")
                        .font(.callout.weight(.semibold))
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            HStack {
                Button("Tekrar dene") {
                    showDownloadSheet = true
                    Task { await manager.startDownload(for: variant) }
                }
                Button("Sıfırla") {
                    manager.cancelDownload(for: variant)
                }
            }
        }
    }

    private var engineHint: String {
        switch settings.enginePreference {
        case "auto":
            return "Cihazına göre en hızlı motoru seçer. Apple Silicon'da Core ML (ANE), ölçüm 5× daha hızlı ncnn'den (docs/BENCHMARKS.md). Core ML yüklenemezse ncnn'e düşer."
        case "coreml":
            return "Core ML, Apple Neural Engine üzerinden çalışır. Tüm 1026 model katmanı ANE'de (100% delegation). 4× upscale, sabit. Bench: 5.2× ncnn'den hızlı."
        default:
            return "ncnn-vulkan subprocess, MoltenVK → Metal GPU. 2× / 3× / 4× upscale, 5 model varyantı. Faz 1 path."
        }
    }

}
