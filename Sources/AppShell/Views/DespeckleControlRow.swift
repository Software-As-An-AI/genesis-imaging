import SwiftUI
import ImagingCore

/// Compact two-row control for Smart Output Phase 3 despeckle:
///   - Checkbox toggle: "☑ Otomatik leke temizle"
///   - Preset picker (segmented, 3 options) shown ONLY when toggle is ON
///   - Dynamic hint caption below
///
/// Disabled when `SettingsStore.shared.smartOutputMode == .off` (despeckle
/// runs inside the Smart Output pipeline, so it has no effect with the
/// pipeline disabled).
///
/// Used in both `BatchQueueView` header and `MainView` (single-file flow).
@MainActor
struct DespeckleControlRow: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Toggle(isOn: $settings.despeckleEnabled) {
                    Text("Otomatik leke temizle")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                .disabled(smartOutputDisabled)

                if settings.despeckleEnabled && !smartOutputDisabled {
                    Picker("", selection: presetBinding) {
                        ForEach(DespecklePreset.allCases, id: \.self) { preset in
                            Text(presetShortLabel(preset)).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .labelsHidden()
                }

                Spacer()
            }

            if !smartOutputDisabled, settings.despeckleEnabled {
                let preset = DespecklePreset.from(rawValue: settings.despecklePreset)
                Text(preset.hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if smartOutputDisabled {
                Text("Smart Output kapalı — leke temizleme uygulanmaz.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var smartOutputDisabled: Bool {
        settings.smartOutputMode == .off
    }

    private var presetBinding: Binding<DespecklePreset> {
        Binding(
            get: { DespecklePreset.from(rawValue: settings.despecklePreset) },
            set: { settings.despecklePreset = $0.rawValue }
        )
    }

    private func presetShortLabel(_ p: DespecklePreset) -> String {
        switch p {
        case .soft:   return "Yumuşak"
        case .normal: return "Normal"
        case .strong: return "Agresif"
        }
    }
}
