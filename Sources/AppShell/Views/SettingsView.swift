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
                    Text("ncnn").tag("ncnn")
                    Text("CoreML (Faz 2 — yakında)").tag("coreml")
                        .disabled(true)
                }
                .pickerStyle(.menu)
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
}
