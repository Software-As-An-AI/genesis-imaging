import Foundation

/// Single source of truth for the SDXL Core ML bundle Phase A.2 ships.
///
/// Apple's official mixed-bit-palettization repo on Hugging Face — pre-compiled
/// `.mlmodelc` directories inside a single zip, openrail++ license,
/// anonymous-pull OK.
///
/// SHA256 + size pinned via `scripts/fetch-sdxl-coreml-model.sh` (drift CI runs
/// weekly to detect upstream re-uploads — see `.github/workflows/sdxl-pin-drift.yml`).
///
/// When changing the default variant (e.g. switching to base 7.04 GB on quality
/// complaints), update `Model.defaultVariant` only — `ModelDownloadManager` +
/// `StableDiffusionCoreMLEngine` read through this catalog.
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

        public var humanLabel: String {
            switch self {
            case .palettized:     return "Apple Base SDXL"
            case .base:           return "Base (yedek)"
            case .iosSplitEinsum: return "iOS split-einsum"
            case .loraColoring:   return "Çocuk Boyama Kitabı (LoRA)"
            }
        }

        /// Whether the variant is offered to the customer in Settings'
        /// Görüntü Oluşturma picker. `.base` / `.iosSplitEinsum` are
        /// developer fallbacks only.
        public var isUserSelectable: Bool {
            switch self {
            case .palettized, .loraColoring:    return true
            case .base, .iosSplitEinsum:        return false
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
            case .base, .iosSplitEinsum:
                return nil
            }
        }

        public var expectedSizeBytes: Int64 {
            switch self {
            case .palettized:     return 6_711_666_087
            case .loraColoring:   return 6_432_524_320
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
            }
        }

        /// Default prompt seeded into GenerationViewModel when the variant is
        /// active. User can edit freely; this is just the initial value.
        ///
        /// The LoRA variant prepends the trigger words `ColoringBookAF, Coloring
        /// Book` per the CivitAI model card — they activate the LoRA's coloring
        /// book aesthetic strongly. If the user removes the triggers, the LoRA
        /// effect weakens but generation still works.
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
            }
        }
    }
}
