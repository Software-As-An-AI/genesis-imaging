import SwiftUI
import ImagingCore

@main
struct ImageUpscaleApp: App {
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
    }
}
