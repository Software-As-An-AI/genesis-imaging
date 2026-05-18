import Foundation
import Observation
import ImagingCore
import CoreMLEngine

/// State + actions for the Generate section UI. Mirrors `UpscaleViewModel`
/// shape (state enum, async start/cancel, output URL surfaced on completion).
///
/// v0.4.0.0 ships the scaffold — when the customer taps "Generate" with the
/// SDXL bundle absent, the engine surfaces `.modelNotInstalled` and the UI
/// guides them through download from Settings. Real inference lands when
/// `StableDiffusionCoreMLEngine.generate` is wired (v0.4.0.1).
@Observable
@MainActor
public final class GenerationViewModel {
    public enum State: Equatable {
        case idle
        /// Engine spinning up — pipeline init + loadResources. First launch
        /// can take 30-120 s while ML compilation happens. No step counter
        /// available yet (UNet loop hasn't started).
        case loading
        case running(step: Int, total: Int)
        case completed(URL, seed: UInt32)
        case failed(String)
    }

    /// Initial prompt comes from the currently-selected variant's
    /// `defaultPrompt` (so the LoRA variant ships trigger words pre-filled).
    /// User edits freely from there.
    public var prompt: String
    public var negativePrompt: String
    public var steps: Int
    public var cfgScale: Double
    public var width: Int
    public var height: Int
    public var seed: UInt32 = 0
    public var randomSeed: Bool = true

    public private(set) var state: State = .idle
    public private(set) var engineName: String = ""

    /// Tracks the variant the prompt/negativePrompt were seeded from. When
    /// the user changes variant in Settings, GenerateView calls
    /// `applyVariantDefaults()` to refresh — but only if user hasn't
    /// already typed anything new (we don't want to silently nuke their
    /// custom prompt).
    private var seededFromVariant: SDXLModelCatalog.Variant

    private var task: Task<Void, Never>? = nil

    public init() {
        let settings = SettingsStore.shared
        let variant = settings.sdxlModelVariantTyped
        self.prompt = variant.defaultPrompt
        self.negativePrompt = variant.defaultNegativePrompt
        self.seededFromVariant = variant
        self.steps = settings.defaultGenerationSteps
        self.cfgScale = settings.defaultGenerationCFG
        let (w, h) = Self.parseSize(settings.defaultGenerationSize)
        self.width = w
        self.height = h
    }

    /// Re-seed prompt + negativePrompt from the currently-selected variant
    /// IF the user hasn't already customized them (still equal to the last
    /// variant's defaults). Idempotent.
    public func applyVariantDefaults() {
        let variant = SettingsStore.shared.sdxlModelVariantTyped
        guard variant != seededFromVariant else { return }

        let promptUnchanged = (prompt == seededFromVariant.defaultPrompt)
        let negUnchanged = (negativePrompt == seededFromVariant.defaultNegativePrompt)

        if promptUnchanged { prompt = variant.defaultPrompt }
        if negUnchanged { negativePrompt = variant.defaultNegativePrompt }
        seededFromVariant = variant
    }

    public var isRunning: Bool {
        switch state {
        case .running, .loading: return true
        default: return false
        }
    }

    public func start() {
        guard !isRunning else { return }
        let actualSeed = randomSeed ? UInt32.random(in: 0..<UInt32.max) : seed
        let request = GenerationRequest(
            prompt: prompt,
            negativePrompt: negativePrompt,
            seed: actualSeed,
            steps: steps,
            cfgScale: cfgScale,
            width: width,
            height: height
        )
        state = .loading
        // Phase A.4: engine resolved from current variant via factory —
        // .palettized / .loraColoring → StableDiffusionCoreMLEngine,
        // .fluxKlein → Flux2KleinEngine (Step 4 fleshes inference).
        let engine = GenerationEngineFactory.engineForCurrentVariant()
        engineName = engine.engineName

        task = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in engine.generate(request: request) {
                    if Task.isCancelled { break }
                    await self.handle(event: event, request: request)
                }
            } catch {
                self.state = .failed(self.describe(error))
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if isRunning { state = .idle }
    }

    private func handle(event: GenerationProgress, request: GenerationRequest) async {
        switch event {
        case .started:
            // Keep `.loading` — engine emits .started before loadResources;
            // first .step event will transition us to .running.
            if case .loading = state {} else { state = .loading }
        case .step(let current, let total):
            state = .running(step: current, total: total)
        case .completed(let result):
            state = .completed(result.outputURL, seed: result.seed)
        case .failed(let err):
            state = .failed(describe(err))
        }
    }

    private func describe(_ error: Error) -> String {
        if let g = error as? GenerationError {
            switch g {
            case .modelNotInstalled:
                return "SDXL modeli henüz indirilmedi. Ayarlar → Görüntü Oluşturma'dan indirin."
            case .modelLoadFailed(let m): return "Model yüklenemedi: \(m)"
            case .invalidPrompt(let m):   return "Prompt geçersiz: \(m)"
            case .inferenceFailed(let m): return "Üretim hatası: \(m)"
            case .ioError(let m):         return "Dosya hatası: \(m)"
            }
        }
        return error.localizedDescription
    }

    private static func parseSize(_ raw: String) -> (Int, Int) {
        let parts = raw.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else {
            return (GenerationDefaults.width, GenerationDefaults.height)
        }
        return (parts[0], parts[1])
    }
}
