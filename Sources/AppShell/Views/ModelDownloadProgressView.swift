import SwiftUI
import ImagingCore

/// Modal sheet that surfaces SDXL bundle download lifecycle (download +
/// verify + extract). Triggered from the Generate banner and Settings
/// status row when the customer taps İndir.
///
/// Why a sheet (not inline progress): the 6.71 GB download takes 5-30 min
/// on typical residential connections; an inline progress bar in a tab the
/// customer scrolls away from feels lost. The sheet is explicit + dismissible
/// ("Arka planda devam et") while the underlying `ModelDownloadManager`
/// keeps running on the singleton actor.
///
/// Auto-dismiss on `.ready` after 1.5s — enough time to read the success
/// state but not blocking the customer from generating.
@MainActor
struct ModelDownloadProgressView: View {
    @Binding var isPresented: Bool
    @State private var manager = ModelDownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            actionRow
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 560,
               minHeight: 240, idealHeight: 280)
        .onChange(of: manager.phase) { _, newPhase in
            if case .ready = newPhase {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isPresented = false
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: headerIcon)
                .foregroundStyle(headerTint)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("SDXL modeli")
                    .font(.headline)
                Text("Apple Core ML · ~6.7 GB · openrail++")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var headerIcon: String {
        switch manager.phase {
        case .ready: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .verifying, .extracting: return "gear.badge"
        default: return "arrow.down.circle"
        }
    }

    private var headerTint: Color {
        switch manager.phase {
        case .ready: return .green
        case .failed: return .orange
        default: return .accentColor
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch manager.phase {
        case .idle:
            idleContent
        case .downloading(let bytes, let total, let throughput, let eta):
            downloadingContent(bytes: bytes, total: total,
                               throughput: throughput, eta: eta)
        case .verifying:
            spinnerContent(label: "Bütünlük doğrulanıyor (SHA256)…",
                           sub: "Dosya boyutu büyük — bu adım birkaç dakika sürebilir.")
        case .extracting:
            spinnerContent(label: "Model arşivi açılıyor…",
                           sub: "Bir kez yapılır, sonraki açılışlarda gerek yok.")
        case .ready:
            readyContent
        case .failed(let message):
            failedContent(message: message)
        }
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("İndirme henüz başlamadı.")
                .font(.callout)
            Text("Aşağıdaki İndir butonuna tıkla; ilk açılış için ~6.7 GB Core ML modeli indirilecek. İndirme bir kez yapılır.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func downloadingContent(bytes: Int64, total: Int64,
                                    throughput: Double?, eta: Int?) -> some View {
        let progress = total > 0 ? Double(bytes) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: progress)
            HStack(spacing: 8) {
                Text(String(format: "%.1f%%", progress * 100))
                    .font(.callout.monospacedDigit().weight(.semibold))
                Text(byteCount(bytes) + " / " + byteCount(total))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 10) {
                if let bps = throughput {
                    Label(byteCount(Int64(bps)) + "/s", systemImage: "speedometer")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if let eta {
                    Label(etaLabel(eta), systemImage: "clock")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    private func spinnerContent(label: String, sub: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.callout.weight(.semibold))
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model hazır")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
            Text("Üret bölümünden artık görüntü oluşturabilirsin. Bu pencere kapanıyor…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failedContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("İndirme başarısız")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    // MARK: - Action row

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            Spacer()
            switch manager.phase {
            case .idle, .failed:
                Button("Kapat") { isPresented = false }
                Button(manager.phase == .idle ? "İndir" : "Tekrar dene") {
                    Task { await manager.startDownload() }
                }
                .buttonStyle(.borderedProminent)
            case .downloading:
                Button("Arka planda devam et") { isPresented = false }
                Button("İptal", role: .cancel) {
                    manager.cancelDownload()
                }
            case .verifying, .extracting:
                Button("Arka planda devam et") { isPresented = false }
            case .ready:
                Button("Kapat") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Formatting

    private func byteCount(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    private func etaLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "~\(seconds) sn kaldı" }
        let m = seconds / 60
        let s = seconds % 60
        if s == 0 { return "~\(m) dk kaldı" }
        return "~\(m) dk \(s) sn kaldı"
    }
}
