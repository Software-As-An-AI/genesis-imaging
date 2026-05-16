import SwiftUI
import ImagingCore

/// Compact two-row control for Smart Output post-process toggles:
///   Row 1: Despeckle (CCA artifact cleanup) — toggle + 3-preset segmented
///   Row 2: Line Art Enhance (halo suppression) — toggle + 3-preset segmented
///
/// Hint text moved to `.help()` tooltips (hover-only) for a tighter layout.
/// Both controls disable when `smartOutputMode == .off`.
@MainActor
struct DespeckleControlRow: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlRow(
                title: "Otomatik leke temizle",
                tooltip: smartOutputDisabled
                    ? "Smart Output kapalı — leke temizleme uygulanmaz"
                    : DespecklePreset.from(rawValue: settings.despecklePreset).hint,
                enabledBinding: $settings.despeckleEnabled,
                presetBinding: despecklePresetBinding,
                allPresets: DespecklePreset.allCases.map { ($0, presetShortLabel($0)) }
            )

            controlRow(
                title: "Çizgi netleştir (halo bastır)",
                tooltip: smartOutputDisabled
                    ? "Smart Output kapalı — çizgi netleştirme uygulanmaz"
                    : LineArtEnhancePreset.from(rawValue: settings.lineArtEnhancePreset).hint,
                enabledBinding: $settings.lineArtEnhanceEnabled,
                presetBinding: enhancePresetBinding,
                allPresets: LineArtEnhancePreset.allCases.map { ($0, enhancePresetShortLabel($0)) }
            )
        }
    }

    @ViewBuilder
    private func controlRow<P: Hashable>(
        title: String,
        tooltip: String,
        enabledBinding: Binding<Bool>,
        presetBinding: Binding<P>,
        allPresets: [(P, String)]
    ) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: enabledBinding) {
                Text(title)
                    .font(.callout)
            }
            .toggleStyle(.checkbox)
            .disabled(smartOutputDisabled)
            .help(tooltip)

            if enabledBinding.wrappedValue && !smartOutputDisabled {
                Picker("", selection: presetBinding) {
                    ForEach(allPresets, id: \.0) { (preset, label) in
                        Text(label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .labelsHidden()
                .help(tooltip)
            }

            Spacer()
        }
    }

    // MARK: - Bindings + labels

    private var smartOutputDisabled: Bool {
        settings.smartOutputMode == .off
    }

    private var despecklePresetBinding: Binding<DespecklePreset> {
        Binding(
            get: { DespecklePreset.from(rawValue: settings.despecklePreset) },
            set: { settings.despecklePreset = $0.rawValue }
        )
    }

    private var enhancePresetBinding: Binding<LineArtEnhancePreset> {
        Binding(
            get: { LineArtEnhancePreset.from(rawValue: settings.lineArtEnhancePreset) },
            set: { settings.lineArtEnhancePreset = $0.rawValue }
        )
    }

    private func presetShortLabel(_ p: DespecklePreset) -> String {
        switch p {
        case .soft:   return "Yumuşak"
        case .normal: return "Normal"
        case .strong: return "Agresif"
        }
    }

    private func enhancePresetShortLabel(_ p: LineArtEnhancePreset) -> String {
        switch p {
        case .soft:   return "Yumuşak"
        case .normal: return "Normal"
        case .strong: return "Agresif"
        }
    }
}
