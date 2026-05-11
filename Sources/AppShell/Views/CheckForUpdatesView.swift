import SwiftUI
import Sparkle

/// SwiftUI wrapper around Sparkle's `SPUUpdater` so the menu item
/// "Güncellemeleri Kontrol Et…" can disable itself when an update check is
/// already in progress. Pattern is the one recommended by the Sparkle
/// documentation for SwiftUI apps:
/// https://sparkle-project.org/documentation/programmatic-setup/#swiftui-app-life-cycle
struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Güncellemeleri Kontrol Et…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
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
