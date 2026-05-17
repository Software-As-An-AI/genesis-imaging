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

        public var humanLabel: String {
            switch self {
            case .palettized:     return "Palettized (önerilen)"
            case .base:           return "Base (yedek)"
            case .iosSplitEinsum: return "iOS split-einsum"
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
            }
        }

        /// SHA256 of the LFS-stored zip — verified post-download via streaming
        /// CryptoKit hash. Pinned only for palettized v1; other variants
        /// require pin before promotion to default.
        public var sha256: String? {
            switch self {
            case .palettized:
                return "a00f335d990588c97c347d97f7e92080f8cb23342c454f4a4d853a59bea1e2b5"
            case .base, .iosSplitEinsum:
                return nil
            }
        }

        public var expectedSizeBytes: Int64 {
            switch self {
            case .palettized:     return 6_711_666_087
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
            }
        }

        /// File or directory names that must exist inside the extracted bundle
        /// before `isInstalled()` returns true. Apple's casing (`VAEDecoder`,
        /// not `VaeDecoder`); tokenizer files required by `StableDiffusion`
        /// package's text encoder load path.
        public var requiredEntries: [String] {
            [
                "TextEncoder.mlmodelc",
                "TextEncoder2.mlmodelc",
                "Unet.mlmodelc",
                "VAEDecoder.mlmodelc",
                "vocab.json",
                "merges.txt",
            ]
        }
    }
}
