import SwiftUI
import ImagingCore
import Sparkle

@main
struct ImageUpscaleApp: App {
    // Sparkle 2.x updater controller. `startingUpdater: true` arms the
    // background scheduler — the app checks SUFeedURL on the
    // `SUScheduledCheckInterval` cadence (24h) baked into Info.plist.
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup("Genesis Imaging") {
            MainView()
                .frame(minWidth: 720, minHeight: 480)
                .task {
                    // Ask for notification permission on first launch.
                    // Sound feedback ('Glass' chime) works even without permission;
                    // banner adds visual cue when allowed.
                    await Notifier.shared.requestAuthorizationIfNeeded()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            // Menubar: "Genesis Imaging → Güncellemeleri Kontrol Et…" appears
            // right after the "About Genesis Imaging" item (.appInfo placement).
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        // macOS Settings scene — ⌘, opens this; menubar "Genesis Imaging > Settings…"
        // wires automatically when this scene is present.
        Settings {
            SettingsView()
        }
    }
}
