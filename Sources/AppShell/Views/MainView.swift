import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImagingCore

/// Faz 1 main surface: drop zone + controls + progress + result.
/// Bound to `UpscaleViewModel` (single source of truth).
///
/// Wave 2 (batch upscale, Faz 3): a `BatchQueue` is owned here and consulted
/// at the top of `body` — when 2+ files arrive (multi-select import or
/// multi-URL drop), `BatchQueueView` replaces the single-file UX. The
/// single-file path stays byte-for-byte preserved when the queue is empty.
@MainActor
public struct MainView: View {
    @State private var viewModel = UpscaleViewModel()
    @State private var showFileImporter = false
    @State private var isDropTargeted = false

    /// Owned for the lifetime of the window. Seeded with the same defaults
    /// the single-file picker offers so the batch UI feels continuous.
    @StateObject private var queue = BatchQueue(
        defaultModel: "realesrgan-x4plus",
        defaultScale: 4
    )

    public init() {}

    public var body: some View {
        Group {
            if queue.items.count >= 2 {
                BatchQueueView(queue: queue)
            } else {
                singleFileBody
            }
        }
    }

    /// Pre-Wave-2 single-file UX, preserved verbatim. Reached when the queue
    /// is empty or holds exactly one item (single-file flow drives via
    /// `viewModel`, not the queue — keeps existing tests + UX contract).
    private var singleFileBody: some View {
        VStack(spacing: 16) {
            header
            dropZone
            controls
            progressArea
            resultArea
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                handleSelected(urls: urls)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text("Genesis Imaging")
                .font(.title)
                .fontWeight(.semibold)
            Text("On-device image upscaling — Apple Silicon native")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
            dropZoneContents
                .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .contentShape(Rectangle())
        .onTapGesture { showFileImporter = true }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .accessibilityLabel("Image drop zone")
        .accessibilityHint("Drop an image here or click to browse")
    }

    @ViewBuilder
    private var dropZoneContents: some View {
        if let url = viewModel.inputURL, let image = NSImage(contentsOf: url) {
            VStack(spacing: 8) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 160)
                    .cornerRadius(8)
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.arrow.down")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("Bir görsel sürükle veya tıkla")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Model", selection: $viewModel.modelName) {
                ForEach(supportedModels, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .frame(maxWidth: 260)

            Picker("Scale", selection: $viewModel.scale) {
                ForEach([2, 3, 4], id: \.self) { factor in
                    Text("x\(factor)").tag(factor)
                }
            }
            .frame(maxWidth: 120)

            Spacer()

            actionButton
        }
    }

    private var actionButton: some View {
        Group {
            if case .running = viewModel.state {
                Button(role: .cancel) {
                    viewModel.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.circle")
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button {
                    Task { await viewModel.startUpscale() }
                } label: {
                    Label("Upscale", systemImage: "wand.and.stars")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.inputURL == nil)
            }
        }
    }

    @ViewBuilder
    private var progressArea: some View {
        if case .running = viewModel.state {
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
        } else if viewModel.progress > 0 {
            ProgressView(value: viewModel.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .opacity(0.5)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        switch viewModel.state {
        case .completed(let url):
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Save As…") {
                    saveAs(sourceURL: url)
                }
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        case .idle, .running:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            Text("Engine: \(viewModel.engineName)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Genesis Imaging \(Self.appVersion) — Faz 1+2")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Reads CFBundleShortVersionString from Info.plist at runtime.
    /// Returns "(dev)" if no Info.plist (e.g. `swift run` without bundle).
    private static var appVersion: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !v.isEmpty {
            return "v\(v)"
        }
        return "(dev)"
    }

    // MARK: - Helpers

    private var supportedModels: [String] {
        [
            "realesrgan-x4plus",
            "realesrgan-x4plus-anime",
            "realesr-animevideov3-x4",
            "realesr-animevideov3-x3",
            "realesr-animevideov3-x2",
        ]
    }

    /// Multi-URL drop handler. Loads every dropped URL asynchronously and,
    /// once they've all resolved, dispatches the batch:
    /// - 1 URL → single-file viewModel path (unchanged).
    /// - 2+ URLs → seed the `BatchQueue` and switch to `BatchQueueView`.
    ///
    /// We accumulate URLs across all providers because `NSItemProvider`'s
    /// `loadObject` is async; dispatching per-provider would race the
    /// `count >= 2` check in `body`.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let group = DispatchGroup()
        var collected: [URL] = []
        let lock = NSLock()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    lock.lock()
                    collected.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                handleSelected(urls: collected)
            }
        }
        return true
    }

    /// Route a freshly-selected URL set to the right surface. Single URL
    /// preserves single-file UX; 2+ populates the batch queue (which
    /// triggers `BatchQueueView` via `body`'s conditional).
    private func handleSelected(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count == 1, let first = urls.first {
            viewModel.selectInput(first)
        } else {
            queue.add(urls: urls)
        }
    }

    private func saveAs(sourceURL: URL) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: sourceURL, to: dest)
            } catch {
                // Non-fatal: surface as failure state for visibility.
                viewModel.state = .failed("Save failed: \(error.localizedDescription)")
            }
        }
    }
}
