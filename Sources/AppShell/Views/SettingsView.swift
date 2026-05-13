import SwiftUI
import ImagingCore

@MainActor
public struct SettingsView: View {
    @Bindable private var settings = SettingsStore.shared

    private let modelOptions = [
        "realesrgan-x4plus",
        "realesrgan-x4plus-anime",
        "realesr-animevideov3-x4",
    ]

    private let scaleOptions = [2, 3, 4]

    /// Simple two-mode picker for the main Smart Output section. Anything
    /// other than `.off` and `.adaptive` lives behind the advanced disclosure.
    @State private var showAdvancedSmartOutput: Bool = false

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
                // Tek-toggle ana picker: Smart Auto / Kapalı.
                // Diğer 6 mode advanced disclosure altında.
                Picker("Mod", selection: $settings.smartOutputMode) {
                    Text("Smart Auto").tag(SmartOutputMode.adaptive)
                    Text("Kapalı").tag(SmartOutputMode.off)
                    // Advanced modlar açıkken aynı picker'da görünür kalır
                    // (kullanıcı seçimi korumak için), kapalıyken gizli.
                    if showAdvancedSmartOutput || isAdvancedMode(settings.smartOutputMode) {
                        ForEach(SmartOutputMode.allCases.filter { $0 != .adaptive && $0 != .off }, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
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

                DisclosureGroup("Gelişmiş ayarlar", isExpanded: $showAdvancedSmartOutput) {
                    Text("Smart Auto seçilen sub-mode dosya adının sonuna eklenir (`adaptive-binarize`, `adaptive-lineart`, vb). Tek tek mode seçmek için aşağıdan seç.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)

                    Picker("Tek mod (debug)", selection: $settings.smartOutputMode) {
                        ForEach(SmartOutputMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Hakkında") {
                LabeledContent("Uygulama", value: "Genesis Imaging")
                LabeledContent("Sürüm", value: appVersion)
                LabeledContent("Açıklama", value: "On-device upscaling — Apple Silicon native")
                LabeledContent("ncnn binary", value: ncnnBinaryVersion)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ayarlar")
        .frame(minWidth: 480, minHeight: 420)
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

    private func isAdvancedMode(_ mode: SmartOutputMode) -> Bool {
        mode != .adaptive && mode != .off
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
