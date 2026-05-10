import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImagingCore

/// Faz 1 main surface: drop zone + controls + progress + result.
/// Bound to `UpscaleViewModel` (single source of truth).
@MainActor
public struct MainView: View {
    @State private var viewModel = UpscaleViewModel()
    @State private var showFileImporter = false
    @State private var isDropTargeted = false

    public init() {}

    public var body: some View {
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
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let first = urls.first {
                viewModel.selectInput(first)
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
            Text("Genesis Imaging — Faz 1")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            Task { @MainActor in
                viewModel.selectInput(url)
            }
        }
        return true
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
