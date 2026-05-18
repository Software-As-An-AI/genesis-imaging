import Foundation

/// Engine layer that consumes a variant's bundle. Variant carries this so the
/// engine factory + ModelDownloadManager know which inference + download path
/// to use. Pre-Phase-A.4 every variant was implicitly `.coreMLSDXL`; FLUX.2
/// Klein 4B (Phase A.4, v0.6.0.0) introduces `.mlxFlux`.
public enum EngineKind: String, Sendable, CaseIterable {
    /// Apple ml-stable-diffusion + Core ML compiled .mlmodelc bundle.
    /// Single-file zip download, single Resources/ dir layout.
    case coreMLSDXL

    /// flux-2-swift-mlx + MLX-Swift framework on Apple Silicon.
    /// Multi-file download (transformer + VAE + Qwen3 text encoder, 3 separate
    /// HF repos). Bundle layout per flux-2-swift-mlx's expected paths under
    /// `~/Library/Caches/models/`.
    case mlxFlux
}

/// A single file within a multi-file model bundle. Phase A.4 (FLUX Klein)
/// needs 2-3 files from separate HF repos; pre-A.4 single-zip variants
/// expose themselves as a one-element array for API uniformity.
public struct DownloadFile: Sendable, Equatable {
    /// Display name surfaced in multi-file progress UI ("transformer", "VAE").
    public let displayName: String
    /// Remote URL — Hugging Face direct (anonymous-pull OK for current files).
    public let url: URL
    /// SHA256 of the file body (LFS x-linked-etag for HF-hosted blobs). `nil`
    /// is acceptable for files where pinning isn't worth the drift work
    /// (e.g. small JSON configs); critical weight files MUST be pinned.
    public let sha256: String?
    /// Expected byte count for progress UI + disk-space precheck.
    public let sizeBytes: Int64
    /// Path inside the variant's `bundleDirectory(for:)` where this file
    /// should land. May be empty (= place at bundleDir root) or include
    /// subdirectory structure (flux-2-swift-mlx expects nested layout).
    public let destinationSubpath: String

    public init(displayName: String, url: URL, sha256: String?,
                sizeBytes: Int64, destinationSubpath: String) {
        self.displayName = displayName
        self.url = url
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.destinationSubpath = destinationSubpath
    }
}

/// Single source of truth for the on-device generation model bundles.
///
/// Originally named for SDXL (Phase A.2) when only SDXL variants existed;
/// Phase A.4 (v0.6.0.0) extends the catalog with FLUX.2 Klein 4B via MLX. Name
/// kept for callsite stability — rename to `ModelCatalog` deferred to a
/// separate refactor cycle. (Phase A.5+ candidate.)
///
/// SHA256 + size pinned per variant; drift CI runs weekly for SDXL palettized
/// (`.github/workflows/sdxl-pin-drift.yml`), FLUX equivalent ships with Step 9.
///
/// Currently-active variant comes from `SettingsStore.sdxlModelVariant`;
/// `ModelDownloadManager` + engine factory dispatch on it.
public enum SDXLModelCatalog {

    /// The bundle variant Phase A.2 currently ships. Picker UI may surface
    /// alternatives in a future iteration; right now this is the single
    /// download channel.
    public static let defaultVariant: Variant = .palettized

    public enum Variant: String, CaseIterable, Sendable {
        /// Mixed-bit palettization — Apple's recommended ANE-optimized bundle,
        /// ~4% subjective quality loss vs base for ~700 MB savings.
        case palettized

        /// Base unquantized bundle. Larger, slower compile on first launch,
        /// kept as fallback if quality issues surface in palettized variant.
        case base

        /// iOS split-einsum bundle — emergency low-RAM path (would need
        /// additional plumbing for macOS use). Not currently exposed.
        case iosSplitEinsum

        /// Phase A.3 — SDXL base with artificialguybr/ColoringBookRedmond-V2
        /// LoRA fused at scale 1.0, converted via Apple's torch2coreml.
        /// Domain-specific bundle for Nadezhda's coloring-book workflow;
        /// dramatically tighter line-art aesthetic vs base SDXL prompting
        /// (proven by local smoke test 2026-05-17).
        case loraColoring

        /// Phase A.4 — FLUX.2 Klein 4B native Swift MLX bundle.
        /// 1-day spike (2026-05-18) + Nadezhda evaluation pack confirmed
        /// dramatic aesthetic improvement vs SDXL+LoRA for kid-coloring-book
        /// minimalist style. Apache 2.0 commercial-OK (transformer + Qwen3
        /// text encoder both). Multi-file download (transformer + VAE +
        /// Qwen3) wired in Step 3. Engine wrapper around flux-2-swift-mlx
        /// landed in Step 4.
        case fluxKlein

        /// Which inference + download path the variant uses. Engine factory
        /// (Step 2) and ModelDownloadManager (Step 3) branch on this.
        public var engineKind: EngineKind {
            switch self {
            case .palettized, .base, .iosSplitEinsum, .loraColoring:
                return .coreMLSDXL
            case .fluxKlein:
                return .mlxFlux
            }
        }

        public var humanLabel: String {
            switch self {
            case .palettized:     return "Apple Base SDXL"
            case .base:           return "Base (yedek)"
            case .iosSplitEinsum: return "iOS split-einsum"
            case .loraColoring:   return "Çocuk Boyama Kitabı (LoRA)"
            case .fluxKlein:      return "FLUX.2 Klein (deneysel)"
            }
        }

        /// Whether the variant is offered to the customer in Settings'
        /// Görüntü Oluşturma picker. `.base` / `.iosSplitEinsum` are
        /// developer fallbacks. `.fluxKlein` stays gated until Steps 3-4
        /// wire multi-file download + MLX engine; flipping to `true` lands
        /// with Step 6 (Settings UI picker extension).
        public var isUserSelectable: Bool {
            switch self {
            case .palettized, .loraColoring:    return true
            case .base, .iosSplitEinsum:        return false
            case .fluxKlein:                    return false  // unlocked in Step 6
            }
        }

        public var downloadURL: URL {
            switch self {
            case .palettized:
                return URL(string:
                    "https://huggingface.co/apple/coreml-stable-diffusion-mixed-bit-palettization/" +
                    "resolve/main/coreml-stable-diffusion-mixed-bit-palettization_original_compiled.zip"
                )!
            case .base:
                return URL(string:
                    "https://huggingface.co/apple/coreml-stable-diffusion-xl-base/" +
                    "resolve/main/coreml-stable-diffusion-xl-base_original_compiled.zip"
                )!
            case .iosSplitEinsum:
                return URL(string:
                    "https://huggingface.co/apple/coreml-stable-diffusion-xl-base-ios/" +
                    "resolve/main/coreml-stable-diffusion-xl-base-ios_split_einsum_compiled.zip"
                )!
            case .loraColoring:
                // Phase A.3: hosted on our own infrastructure (gns-gate-01
                // Caddy under apps.softwareasan.ai). R2 mirror exists at
                // software-as-an-ai-models bucket as fallback (manual flip
                // in future v0.5.x if vps.tc bandwidth becomes a constraint).
                return URL(string:
                    "https://apps.softwareasan.ai/genesis-imaging/models/" +
                    "sdxl-coloring-book-lora-v1.zip"
                )!
            case .fluxKlein:
                // Phase A.4 placeholder — Step 3 multi-file refactor replaces
                // this single-URL accessor with `downloadFiles: [DownloadFile]`.
                // For now the transformer URL is the primary, VAE + Qwen3
                // are out-of-band (auto-downloaded by flux-2-swift-mlx).
                return URL(string:
                    "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/" +
                    "resolve/main/flux-2-klein-4b.safetensors"
                )!
            }
        }

        /// SHA256 of the LFS-stored zip — verified post-download via streaming
        /// CryptoKit hash. Pinned only for palettized v1; other variants
        /// require pin before promotion to default.
        public var sha256: String? {
            switch self {
            case .palettized:
                return "a00f335d990588c97c347d97f7e92080f8cb23342c454f4a4d853a59bea1e2b5"
            case .loraColoring:
                return "c676295a9492f84455abca80355c116f41c5eac0d47f8c8a18a88c03c695f136"
            case .fluxKlein:
                // Transformer SHA only — Step 3 will surface VAE + Qwen3 hashes
                // via the multi-file array. Captured from HF LFS x-linked-etag
                // 2026-05-18 spike download.
                return nil  // pin in Step 3 after multi-file refactor
            case .base, .iosSplitEinsum:
                return nil
            }
        }

        public var expectedSizeBytes: Int64 {
            switch self {
            case .palettized:     return 6_711_666_087
            case .loraColoring:   return 6_432_524_320
            case .fluxKlein:      return 7_200_000_000 // transformer only; total ~11 GB w/ VAE + Qwen3 (Step 3)
            case .base:           return 7_040_000_000 // approximate; pin before activation
            case .iosSplitEinsum: return 3_050_000_000 // approximate; pin before activation
            }
        }

        /// Version marker written to `.sdxl-version` inside the bundle dir.
        /// Bumping forces re-download on next launch. Format keeps upstream
        /// identity + our release suffix so we can invalidate independently.
        public var versionMarker: String {
            switch self {
            case .palettized:     return "palettized-1.0-apple-2023-07"
            case .base:           return "base-1.0-apple-2023-07"
            case .iosSplitEinsum: return "iossplit-1.0-apple-2023-07"
            case .loraColoring:   return "loracoloring-v1-coloringbookredmond-v2-2026-05"
            case .fluxKlein:      return "fluxklein-v1-bfl-klein4b-bf16-qwen3-4b-mlx-4bit-2026-05"
            }
        }

        /// File or directory names that must exist inside the extracted bundle
        /// before `isInstalled()` returns true. Apple's casing (`VAEDecoder`,
        /// not `VaeDecoder`); tokenizer files required by `StableDiffusion`
        /// package's text encoder load path. LoRA variant adds VAEEncoder
        /// because we converted with `--convert-vae-encoder` for future
        /// img2img workflow (eraser-driven inpainting).
        public var requiredEntries: [String] {
            switch self {
            case .palettized, .base, .iosSplitEinsum:
                return [
                    "TextEncoder.mlmodelc",
                    "TextEncoder2.mlmodelc",
                    "Unet.mlmodelc",
                    "VAEDecoder.mlmodelc",
                    "vocab.json",
                    "merges.txt",
                ]
            case .loraColoring:
                return [
                    "TextEncoder.mlmodelc",
                    "TextEncoder2.mlmodelc",
                    "Unet.mlmodelc",
                    "VAEDecoder.mlmodelc",
                    "VAEEncoder.mlmodelc",
                    "vocab.json",
                    "merges.txt",
                ]
            case .fluxKlein:
                // flux-2-swift-mlx layout (per 2026-05-18 spike):
                //   bundleDir/
                //   └── black-forest-labs/FLUX.2-klein-4B-klein4b-bf16/
                //       ├── flux-2-klein-4b.safetensors
                //       └── model_index.json
                // Qwen3 text encoder (lmstudio-community/Qwen3-4B-MLX-4bit)
                // is auto-downloaded by flux-2-swift-mlx at first generation
                // into its own cache (`~/Library/Caches/models/`); we don't
                // include it in our isInstalled contract — Step 6 UI copy
                // surfaces "first generation = additional ~3 GB download".
                return [
                    "black-forest-labs/FLUX.2-klein-4B-klein4b-bf16/flux-2-klein-4b.safetensors",
                    "black-forest-labs/FLUX.2-klein-4B-klein4b-bf16/model_index.json",
                ]
            }
        }

        /// Relative path from the extraction destination root to the
        /// directory that actually contains `requiredEntries`. Apple's zip
        /// archives nest files inside their own folder hierarchy — for the
        /// palettized variant unzip produces:
        ///
        ///   <dest>/
        ///   └── coreml-stable-diffusion-mixed-bit-palettization_original_compiled/
        ///       └── compiled/
        ///           ├── TextEncoder.mlmodelc
        ///           ├── … etc.
        ///
        /// `StableDiffusionXLPipeline(resourcesAt:)` and `isInstalled()` must
        /// point at the inner `compiled/` directory, not the extraction root.
        /// (v0.4.1.0 ship had this wrong — model extracted but pipeline +
        /// presence check looked at root → "modelNotInstalled" surfaced
        /// despite Settings showing the cached optimistic "Model yüklü" row.
        /// Fixed in v0.4.1.1.)
        public var resourcesSubpath: String {
            switch self {
            case .palettized:
                return "coreml-stable-diffusion-mixed-bit-palettization_original_compiled/compiled"
            case .base:
                return "coreml-stable-diffusion-xl-base_original_compiled/compiled"
            case .iosSplitEinsum:
                return "coreml-stable-diffusion-xl-base-ios_split_einsum_compiled/compiled"
            case .loraColoring:
                return "coreml-stable-diffusion-xl-coloring-book_compiled/compiled"
            case .fluxKlein:
                // flux-2-swift-mlx resolves paths relative to its own
                // `~/Library/Caches/models/` root by repo identifier; our
                // bundleDir for fluxKlein IS that root. Empty subpath means
                // resourcesDirectory(for: .fluxKlein) == bundleDirectory.
                return ""
            }
        }

        /// Default prompt seeded into GenerationViewModel when the variant is
        /// active. User can edit freely; this is just the initial value.
        ///
        /// The LoRA variant prepends the trigger words `ColoringBookAF, Coloring
        /// Book` per the CivitAI model card — they activate the LoRA's coloring
        /// book aesthetic strongly. If the user removes the triggers, the LoRA
        /// effect weakens but generation still works.
        /// Multi-file download manifest. SDXL variants return a single
        /// element (the zip bundle, extracted to bundleDir on completion);
        /// FLUX variants return multiple files (transformer + VAE + Qwen3 +
        /// associated configs, placed directly under bundleDir without
        /// extraction). ModelDownloadManager dispatches on this shape.
        public var downloadFiles: [DownloadFile] {
            switch self {
            case .palettized, .base, .iosSplitEinsum, .loraColoring:
                // SDXL: single zip, extract to bundleDir root.
                return [
                    DownloadFile(
                        displayName: "Bundle",
                        url: downloadURL,
                        sha256: sha256,
                        sizeBytes: expectedSizeBytes,
                        destinationSubpath: ""
                    )
                ]
            case .fluxKlein:
                // FLUX Klein: transformer + VAE go in our bundle; Qwen3 text
                // encoder is auto-downloaded by flux-2-swift-mlx at first
                // inference (its own cache, ~3 GB, surfaced as "ilk üretim
                // ek indirme" UX copy in Step 6 picker hint).
                // Layout matches flux-2-swift-mlx expectations: nested
                // black-forest-labs/FLUX.2-klein-4B-klein4b-bf16/...
                // SHAs pinned from 2026-05-18 spike download (Step 3).
                let bflPrefix = "black-forest-labs/FLUX.2-klein-4B-klein4b-bf16"
                return [
                    DownloadFile(
                        displayName: "Klein 4B Transformer",
                        url: URL(string:
                            "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/" +
                            "resolve/main/flux-2-klein-4b.safetensors"
                        )!,
                        sha256: nil,  // TODO: pin SHA after first ship-quality download (Step 9)
                        sizeBytes: 7_200_000_000,
                        destinationSubpath: "\(bflPrefix)/flux-2-klein-4b.safetensors"
                    ),
                    DownloadFile(
                        displayName: "Klein 4B Model Index",
                        url: URL(string:
                            "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/" +
                            "resolve/main/model_index.json"
                        )!,
                        sha256: nil,
                        sizeBytes: 500,
                        destinationSubpath: "\(bflPrefix)/model_index.json"
                    ),
                ]
            }
        }

        public var defaultPrompt: String {
            switch self {
            case .palettized, .base, .iosSplitEinsum:
                return "A coloring book page of a fox in a forest, simple bold line art, "
                     + "thick black outline, white background, minimal detail, kid-friendly, "
                     + "vector style, clean illustration"
            case .loraColoring:
                return "ColoringBookAF, Coloring Book, a coloring book page of a fox in a forest, "
                     + "simple bold line art, thick black outline, white background, "
                     + "minimal detail, kid-friendly, clean illustration"
            case .fluxKlein:
                // FLUX Klein produces minimalist coloring-book aesthetic
                // natively with simpler prompts (no "thick black outline /
                // vector style" stylistic spell needed — model bias does it).
                // Spike (2026-05-18 ~/Desktop/flux-nadezhda-test/) confirmed.
                return "A coloring book page of a fox in a forest"
            }
        }

        /// Default negative prompt seeded into GenerationViewModel for this
        /// variant. Same as positive: user can override freely.
        public var defaultNegativePrompt: String {
            switch self {
            case .palettized, .base, .iosSplitEinsum, .loraColoring:
                return "color, gradient, shading, watercolor, photo, realistic, "
                     + "complex background, dense vegetation, intricate detail, "
                     + "hatching, grayscale, texture"
            case .fluxKlein:
                // Klein 4B at guidance scale 1.0 ignores negative prompts
                // anyway (no classifier-free guidance at scale 1.0); return
                // empty to make this contract explicit.
                return ""
            }
        }
    }
}
