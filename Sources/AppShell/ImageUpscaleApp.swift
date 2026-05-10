import SwiftUI

@main
struct ImageUpscaleApp: App {
    var body: some Scene {
        WindowGroup("Genesis Imaging") {
            MainView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.titleBar)
    }
}
