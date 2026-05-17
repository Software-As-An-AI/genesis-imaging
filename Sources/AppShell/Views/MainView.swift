import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImagingCore
import NcnnEngine
import CoreMLEngine

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
    @State private var eraserSession: EraserSession? = nil
    @State private var eraserLoadError: String? = nil

    // v0.4.0.0: top-level section switch — Generate / Upscale / Edit.
    // Upscale is the historical default; Generate gates on SDXL model
    // download (handled inside GenerateView). Edit (eraser) is reachable
    // via row actions OR by being routed from Generate's result panel.
    @State private var activeSection: MainSection = .upscale

    enum MainSection: String, CaseIterable, Identifiable {
        case generate, upscale, edit
        var id: String { rawValue }
        var label: String {
            switch self {
            case .generate: return "Üret"
            case .upscale:  return "Büyüt"
            case .edit:     return "Düzenle"
            }
        }
        var icon: String {
            switch self {
            case .generate: return "sparkles"
            case .upscale:  return "arrow.up.right.square"
            case .edit:     return "pencil.tip.crop.circle"
            }
        }
    }

    /// Owned for the lifetime of the window. Seeded with the same defaults
    /// the single-file picker offers so the batch UI feels continuous.
    @StateObject private var queue = BatchQueue(
        defaultModel: "realesrgan-x4plus",
        defaultScale: 4
    )

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            sectionPicker
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            globalFooter
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
        }
    }

    /// Global build-provenance footer — visible on every section. Replaces
    /// the per-section version display so the customer always knows which
    /// build they're testing (operator dev-cycle: "v0.4.1.2 mu daha eski mi?"
    /// — fast visual answer at the bottom edge regardless of tab).
    private var globalFooter: some View {
        HStack(spacing: 8) {
            if !VersionStamp.isRelease {
                Text("DEV")
                    .font(.caption2.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.yellow)
                    .cornerRadius(3)
                    .help("Lokal dev build — \(VersionStamp.summary)")
            }
            Text(VersionStamp.summary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .help("Build provenance — \(VersionStamp.buildDate)")
            Spacer()
            if activeSection == .upscale {
                Text("Engine: \(viewModel.engineName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch activeSection {
        case .generate:
            GenerateView(
                onSendToUpscale: { url in
                    // Route generated image into the single-file upscale flow.
                    viewModel.selectInput(url)
                    activeSection = .upscale
                },
                onSendToEditor: { url in
                    presentEraserSheet(for: url)
                }
            )
        case .upscale:
            if queue.items.count >= 2 {
                BatchQueueView(
                    queue: queue,
                    engineProvider: Self.batchEngineProvider,
                    modelsDirectory: Self.resolvedModelsDirectory
                )
            } else {
                singleFileBody
            }
        case .edit:
            EditSectionPlaceholder(presentEraser: presentEraserSheet)
        }
    }

    private var sectionPicker: some View {
        Picker("", selection: $activeSection) {
            ForEach(MainSection.allCases) { section in
                Label(section.label, systemImage: section.icon).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// Engine provider closure handed to `BatchQueueView`. Resolves the user's
    /// engine preference (Settings → Auto / Core ML / ncnn-vulkan) the same
    /// way `UpscaleViewModel.runStream` does for the single-file flow.
    @Sendable
    private static func batchEngineProvider() async throws -> any UpscaleEngine {
        let pref = await MainActor.run {
            EnginePreference.from(rawValue: SettingsStore.shared.enginePreference)
        }
        return try EngineFactory.makeEngine(preference: pref)
    }

    /// Resolved models directory for pre-flight model-presence checks. Delegates
    /// to `BinaryLocator.defaultModelsDirectory()` — the canonical resolver also
    /// used by `NcnnEngine` for single-file flow (Bundle's `Resources/bin/models`
    /// in packaged `.app`, repo `Resources/bin/models` under `swift run`). Returns
    /// `nil` if neither location resolves (preflight then soft-passes the check).
    private static var resolvedModelsDirectory: URL? {
        try? BinaryLocator.defaultModelsDirectory()
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
        .sheet(item: Binding(
            get: { eraserSession.map { EraserSessionWrapper(session: $0) } },
            set: { newValue in if newValue == nil { eraserSession = nil } }
        )) { wrapper in
            EraserEditorView(
                session: wrapper.session,
                onSaved: { _ in eraserSession = nil },
                onCancel: { eraserSession = nil }
            )
        }
        .alert("Eraser açılamadı", isPresented: Binding(
            get: { eraserLoadError != nil },
            set: { if !$0 { eraserLoadError = nil } }
        )) {
            Button("Tamam", role: .cancel) { eraserLoadError = nil }
        } message: {
            Text(eraserLoadError ?? "")
        }
    }

    private struct EraserSessionWrapper: Identifiable {
        let id = UUID()
        let session: EraserSession
    }

    /// Edit section placeholder — the eraser editor itself is sheet-based,
    /// so this view explains the section and offers a "pick a file" path.
    /// The eraser is also reachable via Upscale row actions (Done items) +
    /// pre-upscale source (v0.3.5.3).
    private struct EditSectionPlaceholder: View {
        let presentEraser: (URL) -> Void
        @State private var showImporter = false

        var body: some View {
            VStack(spacing: 16) {
                Image(systemName: "pencil.tip.crop.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.tertiary)
                Text("Silgi Editörü")
                    .font(.title2)
                Text("Açmak için bir görüntü seçin. Üretilen veya büyütülen dosyalardaki istenmeyen detayları silebilirsiniz.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                Button {
                    showImporter = true
                } label: {
                    Label("Görüntü seç…", systemImage: "photo")
                }
                .buttonStyle(.borderedProminent)
                Text("Veya: Üretim sonrası 'Düzenle' butonu, ya da Büyüt bölümünde done item satırındaki silgi ikonu.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let first = urls.first {
                    presentEraser(first)
                }
            }
        }
    }

    private func presentEraserSheet(for url: URL) {
        do {
            eraserSession = try EraserSession.load(from: url)
        } catch {
            eraserLoadError = "Düzenleyici açılamadı: \(error.localizedDescription)"
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
        VStack(alignment: .leading, spacing: 8) {
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

                if let src = viewModel.inputURL, !isRunning {
                    Button {
                        presentEraserSheet(for: src)
                    } label: {
                        Label("Düzenle", systemImage: "pencil.tip.crop.circle")
                    }
                    .help("Upscale öncesi kaynağı silgiyle temizle")
                }

                actionButton
            }

            DespeckleControlRow()
        }
    }

    private var isRunning: Bool {
        if case .running = viewModel.state { return true }
        return false
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
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .help("Finder'da göster")

                Button {
                    presentEraserSheet(for: url)
                } label: {
                    Label("Düzenle", systemImage: "pencil.tip.crop.circle")
                }
                .help("Silgi düzenleyici aç")

                Button {
                    saveAs(sourceURL: url)
                } label: {
                    Label("Farklı kaydet", systemImage: "square.and.arrow.down")
                }
                .help("Yeni konuma kaydet")
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

    /// Inner upscale-section footer is now empty — version + engine moved up
    /// to MainView's globalFooter so they render across all sections. Keeping
    /// the slot lets us add upscale-section-specific status here later
    /// (e.g. queue depth, tile cache size) without re-plumbing.
    private var footer: some View {
        EmptyView()
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
