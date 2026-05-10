import SwiftUI

@main
struct ImageUpscaleApp: App {
    var body: some Scene {
        WindowGroup("Genesis Imaging") {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.titleBar)
    }
}

// MARK: - Placeholder ContentView (Faz 1 Step 5 swaps with full MainView)

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("Genesis Imaging")
                .font(.title)
                .fontWeight(.semibold)
            Text("On-device image upscaling — Apple Silicon native")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Faz 1 — UI in progress")
                .font(.caption)
                .padding(.top, 8)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
