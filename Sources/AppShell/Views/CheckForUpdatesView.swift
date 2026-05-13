import SwiftUI
import Sparkle

/// SwiftUI wrapper around Sparkle's `SPUUpdater` so the menu item
/// "Güncellemeleri Kontrol Et…" can disable itself when an update check is
/// already in progress. Pattern is the one recommended by the Sparkle
/// documentation for SwiftUI apps:
/// https://sparkle-project.org/documentation/programmatic-setup/#swiftui-app-life-cycle
///
/// **Local dev builds** (no `SUFeedURL` in Info.plist) hide the menu item
/// entirely — otherwise tapping it produces a runtime "must specify SUFeedURL"
/// alert. CI builds always set SUFeedURL via `SU_PUBLIC_KEY` env in
/// `package-app.sh`, so production users always see the menu item.
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    private var hasFeedURL: Bool {
        let url = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        return !(url?.isEmpty ?? true)
    }

    var body: some View {
        if hasFeedURL {
            Button("Güncellemeleri Kontrol Et…") {
                updater.checkForUpdates()
            }
            .disabled(!viewModel.canCheckForUpdates)
        }
        // No SUFeedURL → omit menu item entirely (local dev / unpackaged build).
    }
}

/// Observes the `canCheckForUpdates` KVO-bridged property on `SPUUpdater` so
/// the menu Button can reactively enable/disable itself.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
