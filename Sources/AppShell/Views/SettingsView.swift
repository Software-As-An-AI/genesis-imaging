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
                Picker("Mod", selection: $settings.smartOutputMode) {
                    Text("Kapalı").tag(SmartOutputMode.off)
                    Text("Otomatik (önerilen)").tag(SmartOutputMode.auto)
                    Text("Her Zaman").tag(SmartOutputMode.always)
                }
                .pickerStyle(.segmented)

                Text(smartOutputHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var smartOutputHint: String {
        switch settings.smartOutputMode {
        case .off:
            return "Sıkıştırma yok — motor ne yazdıysa o kalır."
        case .auto:
            return "Boyama kitabı, line art veya sınırlı palet içerik otomatik tespit edilip palet quantization + lossless optimizer ile küçültülür (B/W'de 5-20× azalma, near-lossless). Fotoğraflar dokunulmadan kalır."
        case .always:
            return "Tüm çıktılarda pngquant + oxipng uygulanır. Sürekli ton fotoğraflarda hafif kalite kaybı olabilir."
        }
    }
}
