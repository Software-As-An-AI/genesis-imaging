import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImagingCore

// MARK: - BatchQueueView

/// Multi-file batch upscale surface. Active when `queue.items.count >= 2`.
///
/// Layout (top → bottom):
/// - Header with batch defaults (model + scale), batch output override
///   button, and the primary "Başlat" CTA.
/// - Pre-flight issues banner (when `queue.preflightIssues` is non-empty).
/// - Aggregate progress line ("N / M tamamlandı · ~Xs kalan") visible while
///   processing.
/// - Scrollable item list (one `QueueRowView` per item).
/// - End summary card (visible after `.completed` or `.cancelled`).
/// - Footer affordances: "+ Dosya ekle" + cancel button (only during
///   `.processing`).
///
/// Wave 2 scope: UI scaffold + queue mutation (add / remove / override).
/// Wave 3 wires `queue.preflight()` and `queue.start()` to the engine loop.
@MainActor
public struct BatchQueueView: View {
    @ObservedObject var queue: BatchQueue

    /// Async engine provider — injected by the host (`MainView`) so this view
    /// stays decoupled from `EngineFactory`. Called once at start time;
    /// `BatchQueue` reuses the returned engine across all items.
    let engineProvider: @Sendable () async throws -> any UpscaleEngine

    /// Resolved models directory for pre-flight model-presence checks.
    /// `nil` skips the check (engine init will surface missing-model errors
    /// at start time as a per-item failure).
    let modelsDirectory: URL?

    @State private var openOverridePopoverID: UUID?
    @State private var showFileImporter: Bool = false
    @State private var showBatchOutputPicker: Bool = false

    /// Pending re-upscale confirmation: when user picks files via the
    /// importer and some look already upscaled (carry `-upscaled-` segment),
    /// stash them here and surface a confirmDialog. Operator directive
    /// 2026-05-15: re-upscale should be allowed, just opt-in.
    @State private var pendingReUpscale: (fresh: [URL], alreadyUpscaled: [URL])? = nil

    public init(
        queue: BatchQueue,
        engineProvider: @escaping @Sendable () async throws -> any UpscaleEngine,
        modelsDirectory: URL? = nil
    ) {
        self.queue = queue
        self.engineProvider = engineProvider
        self.modelsDirectory = modelsDirectory
    }

    /// Model picker source. Matches the single-file `MainView` list. Wave 3
    /// may unify these via a shared `SupportedModels` table.
    private var supportedModels: [String] {
        [
            "realesrgan-x4plus",
            "realesrgan-x4plus-anime",
            "realesr-animevideov3-x4",
            "realesr-animevideov3-x3",
            "realesr-animevideov3-x2",
        ]
    }

    public var body: some View {
        VStack(spacing: 12) {
            header

            cloudLocationBanner

            if !queue.preflightIssues.isEmpty {
                PreflightIssuesView(queue: queue)
            }

            aggregateProgress

            list

            if queue.phase == .completed || queue.phase == .cancelled {
                endSummary
            }

            Divider()

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
                let parts = FilenameHeuristics.partition(urls)
                if parts.alreadyUpscaled.isEmpty {
                    queue.add(urls: urls)
                } else {
                    // Surface confirmation dialog. Fresh ones can go in
                    // immediately so the user only confirms the duplicates.
                    pendingReUpscale = parts
                }
            }
        }
        .fileImporter(
            isPresented: $showBatchOutputPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let first = urls.first {
                queue.batchOutputOverride = first
            }
        }
        .confirmationDialog(
            reUpscaleDialogTitle,
            isPresented: Binding(
                get: { pendingReUpscale != nil },
                set: { if !$0 { pendingReUpscale = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingReUpscale
        ) { parts in
            Button("Hepsini ekle") {
                queue.add(urls: parts.fresh + parts.alreadyUpscaled)
                pendingReUpscale = nil
            }
            if !parts.fresh.isEmpty {
                Button("Yalnız yeni dosyaları ekle (\(parts.fresh.count))") {
                    queue.add(urls: parts.fresh)
                    pendingReUpscale = nil
                }
            }
            Button("Vazgeç", role: .cancel) {
                pendingReUpscale = nil
            }
        } message: { parts in
            Text("\(parts.alreadyUpscaled.count) dosya zaten daha önce upscale edilmiş gibi görünüyor (`-upscaled-` ile bitiyor). Yeniden upscale dosya adına ek bir suffix bindirir.")
        }
    }

    private var reUpscaleDialogTitle: String {
        guard let parts = pendingReUpscale else { return "" }
        return "\(parts.alreadyUpscaled.count) dosya zaten upscale edilmiş — yine eklensin mi?"
    }

    // MARK: - iCloud Drive warning banner

    @ViewBuilder
    private var cloudLocationBanner: some View {
        let target = queue.batchOutputOverride
            ?? queue.items.first?.sourceURL.deletingLastPathComponent()
        if let dir = target {
            let verdict = CloudLocationDetector.inspect(dir)
            if verdict.isCloudSynced {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Çıktı klasörü: \(verdict.displayName)")
                            .font(.callout.weight(.semibold))
                        Text(verdict.warningMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Klasör seç") { showBatchOutputPicker = true }
                        .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("Toplu yükseltme")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("(\(queue.items.count) dosya)")
                    .foregroundStyle(.secondary)
                Spacer()
                startButton
            }

            HStack(spacing: 12) {
                Picker("Model", selection: $queue.defaultModel) {
                    ForEach(supportedModels, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(maxWidth: 260)
                .disabled(queue.phase == .processing)

                Picker("Ölçek", selection: $queue.defaultScale) {
                    ForEach([2, 3, 4], id: \.self) { factor in
                        Text("x\(factor)").tag(factor)
                    }
                }
                .frame(maxWidth: 120)
                .disabled(queue.phase == .processing)

                Spacer()

                Button {
                    showBatchOutputPicker = true
                } label: {
                    if let override = queue.batchOutputOverride {
                        Label(override.lastPathComponent, systemImage: "folder")
                    } else {
                        Label("Hepsini buraya kaydet…", systemImage: "folder")
                    }
                }
                .help("Tüm çıktıların yazılacağı klasörü seç")

                if queue.batchOutputOverride != nil {
                    Button {
                        queue.batchOutputOverride = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Klasör seçimini temizle (aynı dizine yaz)")
                }
            }
        }
    }

    /// Primary CTA — runs preflight, then (if no issues) hands the queue to
    /// the engine provider. Soft cancel happens via the footer's "İptal".
    private var startButton: some View {
        Button {
            Task {
                let issues = await queue.preflight(modelsDirectory: modelsDirectory)
                guard issues.isEmpty else { return }
                await queue.start(engineProvider: engineProvider)
            }
        } label: {
            Label("Başlat", systemImage: "play.fill")
        }
        .keyboardShortcut(.defaultAction)
        .disabled(startDisabled)
    }

    private var startDisabled: Bool {
        // Wave 2 disablement heuristic: must have items, no open issues, and
        // not already processing/finished. Wave 3 will replace `.draft`-only
        // gating with `phase == .ready` after wiring preflight.
        guard !queue.items.isEmpty else { return true }
        guard queue.preflightIssues.isEmpty else { return true }
        switch queue.phase {
        case .draft, .ready, .validating:
            return false
        case .processing, .completed, .cancelled:
            return true
        }
    }

    // MARK: - Aggregate progress

    @ViewBuilder
    private var aggregateProgress: some View {
        if queue.phase == .processing {
            HStack(spacing: 12) {
                ProgressView(value: aggregateFraction)
                    .progressViewStyle(.linear)
                Text(progressLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// Fraction in [0, 1] = completed / total. Cheap and stable; per-item
    /// fractional progress is shown inside `QueueRowView`.
    private var aggregateFraction: Double {
        guard queue.totalCount > 0 else { return 0 }
        return Double(queue.completedCount) / Double(queue.totalCount)
    }

    /// Composed label: "N / M tamamlandı · ~Xs kalan" — ETA omitted until
    /// `averageDuration` is set (first item completed).
    private var progressLabel: String {
        let prefix = "\(queue.completedCount) / \(queue.totalCount) tamamlandı"
        if let eta = queue.etaSeconds {
            return "\(prefix) · ~\(formatETA(eta)) kalan"
        }
        return "\(prefix) · Hazırlanıyor…"
    }

    /// "<60s" → "Xs", "<60min" → "Xdk Ys", "≥60min" → "Xh Ydk".
    private func formatETA(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 {
            let m = total / 60
            let s = total % 60
            return s == 0 ? "\(m)dk" : "\(m)dk \(s)s"
        }
        let h = total / 3600
        let m = (total % 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)dk"
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(queue.items) { item in
                    QueueRowView(
                        queue: queue,
                        item: item,
                        openOverridePopoverID: $openOverridePopoverID
                    )
                    Divider()
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - End summary

    private var endSummary: some View {
        let doneCount = queue.items.filter { $0.state == .done }.count
        let failedCount = queue.items.filter { $0.state == .failed }.count
        let skippedCount = queue.items.filter { $0.state == .skipped }.count
        let icon = queue.phase == .cancelled
            ? "stop.circle.fill"
            : "checkmark.circle.fill"
        let tint: Color = queue.phase == .cancelled ? .orange : .green
        let headline = queue.phase == .cancelled ? "Toplu işlem iptal edildi" : "Toplu işlem tamamlandı"

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                Text("\(doneCount)/\(queue.totalCount) başarılı · \(failedCount) hata · \(skippedCount) atlandı")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(tint.opacity(0.08))
        .cornerRadius(6)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                showFileImporter = true
            } label: {
                Label("Dosya ekle", systemImage: "plus")
            }
            .disabled(queue.phase == .processing)

            Spacer()

            if queue.phase == .processing {
                Button(role: .cancel) {
                    queue.softCancel()
                } label: {
                    Label("İptal", systemImage: "stop.circle")
                }
                .keyboardShortcut(.cancelAction)
                .disabled(queue.cancelRequested)
            } else if queue.phase == .completed || queue.phase == .cancelled {
                Button {
                    queue.reset()
                } label: {
                    Label("Listeyi temizle", systemImage: "trash")
                }
            }
        }
    }
}
