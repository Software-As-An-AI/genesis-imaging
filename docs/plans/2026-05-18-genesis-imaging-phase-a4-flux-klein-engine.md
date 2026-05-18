# PLAN: Genesis Imaging Phase A.4 — FLUX.2 Klein 4B Engine Variant

**File destination (for MAX to persist):** `/Users/okan.yucel/Desktop/genesisv3/docs/plans/2026-05-18-genesis-imaging-phase-a4-flux-klein-engine.md`

**Plan agent:** genesis-imaging-flux-plan-architect (read-only subagent — cannot write files; MAX persists this output verbatim)
**Cycle:** Phuket 2026-05-18, follows Phase A.3 ship (v0.5.0.0)
**Customer:** Nadezhda (Etsy coloring book + adventure book artist)
**Supersedes:** Phase A.3 plan §6 risk #3 ("FLUX engine swap — Phase B candidate") — research + 1-day spike resolved blocker concerns; Klein 4B Apache 2.0 + flux-2-swift-mlx Swift-native path crystallized.

---

## Substrate Bootstrap Note (CAVEAT)

**`mcp__experience_db__get_relevant_wisdom` was NOT available** in this subagent's tool registry — same gap surfaced by:
- `/tmp/flux-research.md` §Substrate Bootstrap (research-deliverable from 2026-05-17)
- Phase A.3 plan §Substrate Bootstrap Note
- Phase A.2 handoff "experience_db MCP orta-cycle disconnect"

Per the plan-author instructions, this plan is **substrate-blind** and relies on:
- In-prompt operator context (lockdown decisions, spike verdict, customer verdict)
- `/tmp/flux-research.md` (~277 lines, fully consumed)
- `docs/plans/2026-05-17-genesis-imaging-phase-a3-lora-coloring-book.md` (fully consumed — per-variant catalog + manager + engine refactor pattern is reused)
- Direct source reading of `SDXLModelCatalog.swift`, `ModelDownloadManager.swift` (current shipped state, post Phase A.3), `StableDiffusionCoreMLEngine.swift`, `GenerationEngineProtocol.swift`, `Package.swift`

**Wisdom IDs inferred from Phase A.3 handoff** (cited at relevant steps as `(wisdom-inferred: …)`):
- `per-variant-state-namespacing-backward-compat-bridge` — palettized's legacy `sdxl/` subdir is preserved; FLUX gets its own subdir (Step 3).
- `Apple-SwiftPM-bundle-structures-undocumented` — `resourcesSubpath` empirical verification post-download is mandatory for FLUX too (Step 4 verification gate).
- `customer-empirical-iteration` — Nadezhda spike verdict ("kalite daha iyi… bununla ilerleyelim") compresses estimates 3-4× in ship phase (Step 11 buffer sizing).
- `research-decide-plan-execute-decoupling` — this plan is "decide+plan"; MAX executes (Steps 0-11 mechanical-given-this-plan).
- `optimistic-cache-vs-disk-truth` — `isInstalled(for:)` remains the only source of truth; FLUX multi-file path doubles the trust surface (Step 3 verification + Step 4 marker write).
- `r2-bucket-public-access-default-disabled` — Step 10 mirror upload must enable public access AFTER upload (Phase A.3 lesson reused).
- `apple-repo-README-platform-specificity` — flux-2-swift-mlx requires macOS 15 + Apple Silicon; conditional 14 path explicitly rejected (locked decision #1).

**`wisdom-NEW-candidate` for harvest after ship:**
- `multi-file-download-aggregate-progress-pattern` (Step 3)
- `mlx-metallib-bundling-codesign-discipline` (Step 5)
- `macos-major-bump-sparkle-appcast-minimumSystemVersion` (Step 11)
- `bus-factor-1-dep-pin-exact-not-from` (Step 0)

**Follow-up surface for operator:** P0.75 substrate bootstrap requirement still unsatisfiable programmatically from subagents until experience_db MCP is restored. Two consecutive plans now flagged this — escalate beyond backlog noise.

---

## 1. Context (~50 lines)

### Why Phase A.4 now

Phase A.3 (v0.5.0.0) shipped the ColoringBookRedmond-V2 LoRA-on-SDXL variant: ~3 GB R2-hosted bundle, per-variant `ModelDownloadManager` refactor, `SettingsStore.sdxlModelVariantTyped` switching, per-variant default prompts with trigger-prepend. Nadezhda's verdict on the LoRA variant: **insufficient** — better than base SDXL on coloring-book vocabulary, but the per-character anatomy noise + line-weight inconsistency + closed-shape failures that block her commercial Etsy workflow did not collapse to her DALL-E 3 baseline.

The 1-day FLUX spike (2026-05-17) resolved the open question from `/tmp/flux-research.md` §3 ("only a prototype + real Nadezhda test resolves this"):
- **flux-2-swift-mlx v2.1.0 confirmed working** on M4 Pro macOS 15.7.5 with FLUX.2 Klein 4B int4 + 4-step inference at ~35-45 sec / 1024×1024.
- 6-sample evaluation pack shipped at `~/Desktop/flux-nadezhda-test/`.
- **Nadezhda verdict (verbatim):** *"kalite daha iyi, DALL-E/MJ seviyesinde değil ama bu aşama için yeterli — bununla ilerleyelim."*
- Spike artifact at `/Users/okan.yucel/Desktop/genesis-imaging/tools/flux-spike/` (Flux2CLI binary + `mlx.metallib` symlink from `/opt/homebrew/lib/mlx.metallib`).

This unlocks Phase A.4: FLUX.2 Klein 4B as a **third user-selectable engine variant** alongside `.palettized` and `.loraColoring`.

### What FLUX brings that LoRA-on-SDXL didn't

- **Native minimalist coloring book aesthetic** without trigger-word steering — Klein's training corpus + 12B-class architecture produce closed-contour line art on naive prompts, where SDXL+LoRA still requires `ColoringBookAF` trigger + 30 steps + careful negative prompt.
- **Faster wall time:** ~35-45 sec vs ~70 sec (Phase A.2 baseline). Faster iteration loop for Nadezhda's bulk Etsy workflow even if quality is comparable.
- **Better anatomy/finger consistency** (research §1.1) — the most common Nadezhda failure mode on SDXL is fixable by the base model, not just prompt engineering.
- **Apache 2.0 license clean** — commercial Etsy distribution unambiguous (vs `loraColoring`'s OpenRAIL-M "internal-use posture").

### Genuine quality positioning (honest framing — operator-anchored)

**"Better than SDXL, below DALL-E, sufficient for Nadezhda's current workflow."** This phrase is the Settings UI copy anchor, the release notes anchor, the substrate handoff anchor. Do not promise DALL-E parity (research §3, §6 "Honest verdict: C with hedge toward narrow B"). Frame FLUX as *meaningfully better, still preview-class for premium commercial illustration*.

### What's out of scope

- **FLUX dev / FLUX.2 Pro / FLUX.2 Dev 32B** — license (dev) or wall-time (32B = ~35 min) blockers; research §2.4 + §2.5 rule them out.
- **Full-res >1024×1024** — Klein 4B + flux-2-swift-mlx is calibrated for 1024×1024; larger sizes need transformer config changes outside our integration surface.
- **Prompt upsampling** (DALL-E-style GPT-4 prompt rewriter) — meaningful quality lever but separate cycle.
- **LoRA on FLUX** — Phase A.5 trigger condition if Nadezhda's real-workflow verdict on Klein is positive.
- **Cloud DALL-E / GPT-Image-1 hybrid engine** (research §3 Path D) — explicitly deferred.
- **Eraser → img2img on FLUX** — FLUX-img2img surface in flux-2-swift-mlx exists but is out of A.4 scope (Phase B candidate).
- **Quantization knobs in UI** (Klein 4B int4 vs 9B vs 16B) — locked decision #6: int4 only, advanced settings deferred.

---

## 2. Approach (~100 lines)

### Architecture: variant catalog → engine factory → runtime dispatch

```
                          SettingsView picker
                                  │
                                  ▼
              SettingsStore.sdxlModelVariantTyped
                                  │
              ┌───────────────────┴───────────────────┐
              ▼                                       ▼
   ModelDownloadManager                       GenerationViewModel.start()
   .resourcesDirectory(for: variant)                 │
   .isInstalled(for: variant)                        ▼
              │                          let engine = GenerationEngineFactory
              │                                          .engine(for: variant)
              │                                       │
              │                          switch variant.engineKind {
              │                          case .coreMLSDXL:
              │                            StableDiffusionCoreMLEngine(variant: variant)
              │                          case .mlxFlux:
              │                            Flux2KleinEngine(variant: variant)
              │                          }
              │                                       │
              ▼                                       ▼
   ┌──────────────────────┐              ┌──────────────────────┐
   │ Per-variant disk     │              │ Engine.generate(req) │
   │ <Application Support>│              │   AsyncThrowingStream│
   │ /GenesisImaging/     │              └──────────┬───────────┘
   │  models/             │                         │
   │   ├ sdxl/            │ (palettized — legacy)   │
   │   ├ sdxl-lora-...    │ (loraColoring)          │
   │   └ flux-klein-4b/   │ (fluxKlein — NEW)       │
   │      ├ transformer/  │                         │
   │      ├ vae/          │                         │
   │      ├ qwen3-encoder/│                         │
   │      └ .sdxl-version │                         │
   └──────────────────────┘                         │
                                                    ▼
                                    ┌────────────────────────────────┐
                                    │  Core ML SDXL pipeline         │
                                    │    (variants .palettized,      │
                                    │     .loraColoring)             │
                                    │                                │
                                    │  OR                            │
                                    │                                │
                                    │  MLX Swift Flux2Pipeline       │
                                    │    (variant .fluxKlein)        │
                                    │  Requires mlx.metallib at      │
                                    │  Bundle.module.resourceURL/    │
                                    └────────────────────────────────┘
```

### `EngineKind` enum on the Variant — single catalog, dispatched runtime

**Locked decision #2.** Each `SDXLModelCatalog.Variant` carries an `engineKind: EngineKind` computed property:

```swift
public enum EngineKind: String, Sendable {
    case coreMLSDXL   // Apple ml-stable-diffusion via .mlmodelc
    case mlxFlux      // flux-2-swift-mlx via .safetensors + Qwen3 tokens
}

extension SDXLModelCatalog.Variant {
    public var engineKind: EngineKind {
        switch self {
        case .palettized, .base, .iosSplitEinsum, .loraColoring:
            return .coreMLSDXL
        case .fluxKlein:
            return .mlxFlux
        }
    }
}
```

**Why not rename `SDXLModelCatalog` → `ModelCatalog`?** Cost: a rename touches every `SDXLModelCatalog.Variant.X` callsite (~25 hits across the codebase per phase A.3's existing pattern). Benefit: cleaner semantics. **Decision: keep the name `SDXLModelCatalog`** for v0.6.0.0. The name is now technically misleading but a rename is a separate-PR cleanup that doesn't change runtime behaviour. Add a doc comment caveat on the enum: `"// Despite the SDXL prefix, this catalog hosts non-SDXL variants (FLUX) too — rename deferred to v0.7.x"`.

### Multi-file download flow for FLUX

**Diverges from Phase A.3 pattern.** SDXL variants ship a single zip; FLUX needs 3 separately hosted files from Hugging Face:

| Asset | Source | Size approx | License |
|---|---|---|---|
| Klein 4B transformer (int4 safetensors) | `black-forest-labs/FLUX.2-klein-4B` | ~3.5 GB | Apache 2.0 |
| VAE (separate file in same repo) | `black-forest-labs/FLUX.2-klein-4B` | ~0.3 GB | Apache 2.0 (verify in Step 4) |
| Qwen3-4B text encoder (4-bit MLX) | `lmstudio-community/Qwen3-4B-MLX-4bit` | ~2.3 GB | Apache 2.0 |
| **Total bundle on disk** | | **~6.1 GB** | |

Wait — the operator's prompt + the spike + locked decision #8 says "~11 GB" warning. The discrepancy is because flux-2-swift-mlx may download FP16 versions of some assets on first inference if Klein-specific quantized variants aren't present. We will:
1. **Pin the smallest known-good set** (int4 transformer + 4-bit Qwen3 + native VAE).
2. **Surface "~11 GB" in UI copy as the safe upper bound** — undershooting is friendlier than overshooting. (Operator copy lock: "İndir ~11 GB" prevents post-install surprise if flux-2-swift-mlx auto-pulls additional FP16 fallbacks on first run.)
3. Document the empirical-true number in `pin.json` after Step 4 verification download.

Multi-file download contract extension (Step 3 detail):

```swift
public struct VariantDownloadItem: Sendable {
    public let relativePath: String   // e.g. "transformer/flux-2-klein-4b-int4.safetensors"
    public let downloadURL: URL
    public let sha256: String?         // pinned post-spike download
    public let sizeBytes: Int64
}

extension SDXLModelCatalog.Variant {
    public var downloadItems: [VariantDownloadItem] {
        switch self {
        case .fluxKlein:
            return [
                VariantDownloadItem(
                    relativePath: "transformer/flux-2-klein-4b-int4.safetensors",
                    downloadURL: URL(string: "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/resolve/main/flux-2-klein-4b-int4.safetensors")!,
                    sha256: "<PIN_AFTER_SPIKE_HASH>",
                    sizeBytes: 3_500_000_000
                ),
                VariantDownloadItem(
                    relativePath: "vae/flux-2-vae.safetensors",
                    downloadURL: URL(string: "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B/resolve/main/vae/diffusion_pytorch_model.safetensors")!,
                    sha256: "<PIN>",
                    sizeBytes: 300_000_000
                ),
                VariantDownloadItem(
                    relativePath: "qwen3-encoder/model.safetensors",
                    downloadURL: URL(string: "https://huggingface.co/lmstudio-community/Qwen3-4B-MLX-4bit/resolve/main/model.safetensors")!,
                    sha256: "<PIN>",
                    sizeBytes: 2_300_000_000
                ),
                // Plus tokenizer + config files (small, <1 MB each — listed in Step 4)
            ]
        default:
            // Single-item shim around existing single-URL pattern
            return [
                VariantDownloadItem(
                    relativePath: "bundle.zip",
                    downloadURL: self.downloadURL,
                    sha256: self.sha256,
                    sizeBytes: self.expectedSizeBytes
                ),
            ]
        }
    }
}
```

The downloader iterates items, emits aggregate `.downloading(bytes: sumWritten, total: sumTotal, ...)` progress, and writes the version marker only after **all** items verify successfully. Single-file SDXL variants continue to use the existing zip-extract path; FLUX skips extract (safetensors are already final on-disk).

### Metallib bundling

**Locked decision #7.** flux-2-swift-mlx + MLX-Swift at runtime requires `mlx.metallib` resolvable in the app bundle. The spike worked because `Flux2CLI` had a symlink to `/opt/homebrew/lib/mlx.metallib`. For customer ship:

1. Build-time script (`scripts/copy-mlx-metallib.sh`) copies `mlx.metallib` from MLX-Swift's SPM checkout into `Sources/CoreMLEngine/Resources/mlx.metallib` (or a new `FluxEngine` target's Resources — see Step 0 design decision).
2. `Package.swift` resource declaration: `resources: [.copy("Resources/mlx.metallib")]`.
3. At runtime, the FLUX engine code calls `Bundle.module.url(forResource: "mlx", withExtension: "metallib")` and sets the MLX env var (or whichever API MLX-Swift exposes — verify in Step 4 by inspecting `flux-2-swift-mlx` source for metallib discovery).
4. Sparkle inside-out codesign compatibility verified before tag push (Step 11).

### macOS 14 → 15 bump impact

**Locked decision #1.** Bumping `platforms: [.macOS(.v15)]` shuts out customers on Sonoma. Mitigations:
- Sparkle appcast: bump `<minimumSystemVersion>15.0</minimumSystemVersion>` on the v0.6.0.0 entry. Sonoma users stay on v0.5.x (existing variants still work).
- Settings copy: clear "macOS Sequoia (15.0+) gerekli" when FLUX variant is selectable but OS check fails.
- Nadezhda is on macOS 15 (operator confirmed in spike conversation) — primary customer unaffected.
- Operator's M4 Pro is on macOS 15.7.5 — dev box unaffected.

### Per-variant engine instantiation pattern

`GenerationEngineFactory` (new, Step 2) — keeps `GenerationViewModel.start()` engine-agnostic:

```swift
public enum GenerationEngineFactory {
    @MainActor
    public static func engine(for variant: SDXLModelCatalog.Variant) -> any GenerationEngine {
        switch variant.engineKind {
        case .coreMLSDXL:
            return StableDiffusionCoreMLEngine(modelBundleURL: nil)
        case .mlxFlux:
            return Flux2KleinEngine()
        }
    }
}
```

Future engines (Phase B FLUX dev, Phase C cloud DALL-E) extend the switch.

---

## 3. Implementation Steps (~450 lines)

### Step 0: macOS bump + Package.swift dep addition (~0.5 day)

**Goal:** Add flux-2-swift-mlx dependency; bump macOS to 15; confirm 194-test baseline still GREEN.

**Files touched (MODIFIED):**
- `Package.swift` (~+15 LOC):
  ```swift
  // swift-tools-version:5.9
  let package = Package(
      name: "GenesisImaging",
      platforms: [.macOS(.v15)],   // BUMPED FROM .v14
      products: [
          .library(name: "ImagingCore", targets: ["ImagingCore"]),
          .library(name: "NcnnEngine", targets: ["NcnnEngine"]),
          .library(name: "CoreMLEngine", targets: ["CoreMLEngine"]),
          .library(name: "FluxEngine", targets: ["FluxEngine"]),    // NEW
          .executable(name: "GenesisImaging", targets: ["AppShell"]),
      ],
      dependencies: [
          .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
          .package(url: "https://github.com/apple/ml-stable-diffusion", from: "1.1.1"),
          // NEW — pin exact for bus-factor-1 risk (wisdom-NEW-candidate: bus-factor-1-dep-pin-exact)
          .package(url: "https://github.com/VincentGourbin/flux-2-swift-mlx", exact: "2.1.0"),
      ],
      targets: [
          // ... existing targets ...
          .target(
              name: "FluxEngine",
              dependencies: [
                  "ImagingCore",
                  .product(name: "Flux2Core", package: "flux-2-swift-mlx"),
                  .product(name: "FluxTextEncoders", package: "flux-2-swift-mlx"),
                  // Flux2Chains optional — verify needed at Step 4
              ],
              resources: [.copy("Resources/mlx.metallib")],   // Step 5 will populate
              linkerSettings: [
                  .linkedFramework("Metal"),
                  .linkedFramework("MetalPerformanceShaders"),
              ]
          ),
          // AppShell gains FluxEngine dep:
          .executableTarget(
              name: "AppShell",
              dependencies: ["ImagingCore", "NcnnEngine", "CoreMLEngine", "FluxEngine",
                             .product(name: "Sparkle", package: "Sparkle")]
          ),
          // NEW test target:
          .testTarget(
              name: "FluxEngineTests",
              dependencies: ["FluxEngine", "ImagingCore"],
              resources: [.process("Resources")]
          ),
      ]
  )
  ```

  **Design decision: separate `FluxEngine` target vs extending `CoreMLEngine`?** Separate target chosen because:
  1. MLX framework deps don't belong inside CoreMLEngine's symbolic namespace.
  2. Future maintainers grep for "FLUX" → land in one target, not mixed with SDXL plumbing.
  3. If we ever ship a Sonoma-compatible non-FLUX build (theoretical), FluxEngine can be conditionally excluded from AppShell deps at build script level. Cost: +1 target = +1 product = +1 test target. Acceptable.

**Files touched (NEW):**
- `Sources/FluxEngine/` directory (empty for now — Step 4 populates).
- `Sources/FluxEngine/Resources/.gitkeep` (so Resources directory exists for Step 5 metallib copy).

**Verification:**
```bash
cd ~/Desktop/genesis-imaging
swift package resolve     # fetch flux-2-swift-mlx + mlx-swift transitive
swift build               # expect compile success; no FluxEngine code yet so this just resolves
swift test 2>&1 | tail -20   # expect: 194 tests GREEN (Phase A.3 baseline preserved)
```

Pass criteria:
- `swift package resolve` lists `flux-2-swift-mlx` at version `2.1.0` exact.
- `swift build` no errors (FluxEngine target empty Swift sources → empty library is valid SPM).
- 194 existing tests still GREEN. (Bumping `.v14` → `.v15` should be transparent; if a test uses `@available(macOS 14, *)` shim, drop it; if a Sonoma-specific API was used, surface compile error early.)

**Dependency:** none (first step).

**Risk:** flux-2-swift-mlx v2.1.0 transitive deps may pull `mlx-swift` at a version that conflicts with other deps. If so, log the resolved versions tree (`swift package show-dependencies`) and pin the conflicting deps explicitly. Budget 1h debug.

**P0.90 5-layer coverage:**
- **Code:** Package.swift, `Sources/FluxEngine/Resources/.gitkeep`
- **Test:** baseline 194 tests still GREEN (regression guard for macOS bump)
- **Substrate:** commit message captures `wisdom-NEW-candidate: bus-factor-1-dep-pin-exact-not-from` + locked decision #1 rationale
- **Observability:** `swift package show-dependencies` output archived to `docs/proofs/imaging-a4-flux-klein/dep-tree.txt`
- **Living check:** `.github/workflows/swift-build.yml` (if exists) runs on PR; if not, manual `swift build` is the gate.

---

### Step 1: EngineKind enum + Variant.fluxKlein case (~0.5 day)

**Goal:** Additive `SDXLModelCatalog.Variant.fluxKlein` case + `EngineKind` enum + per-variant `engineKind` computed property + `downloadItems` extension.

**Files touched (MODIFIED):**
- `Sources/ImagingCore/Generation/SDXLModelCatalog.swift` (~+120 LOC, no deletions):

  Add to top of `SDXLModelCatalog` enum:
  ```swift
  /// Which runtime executes this variant. Engine layer dispatches via
  /// `GenerationEngineFactory.engine(for:)` reading this property.
  public enum EngineKind: String, Sendable, Equatable {
      case coreMLSDXL
      case mlxFlux
  }
  ```

  Add to `Variant` enum:
  ```swift
  case fluxKlein   // FLUX.2 Klein 4B int4 via flux-2-swift-mlx (MLX/GPU)
  ```

  Extend ALL existing switch statements with `.fluxKlein` arm (`humanLabel`, `isUserSelectable`, `downloadURL`, `sha256`, `expectedSizeBytes`, `versionMarker`, `requiredEntries`, `resourcesSubpath`, `defaultPrompt`, `defaultNegativePrompt`).

  Concrete values:
  - `humanLabel` → `"FLUX.2 Klein (deneysel)"`
  - `isUserSelectable` → `true`
  - `downloadURL` → returns the **transformer** URL only (HF black-forest-labs/FLUX.2-klein-4B/resolve/main/flux-2-klein-4b-int4.safetensors); legacy single-URL API kept for shim compatibility. Real download flow uses `downloadItems`.
  - `sha256` → `nil` initially, pinned post-Step 4 spike-download.
  - `expectedSizeBytes` → `11_000_000_000` (safe upper bound covering all 3 assets + fallback fetches; locked decision #8).
  - `versionMarker` → `"fluxKlein-1.0-int4-mlx-swift-2.1.0-qwen3-4bit-2026-05"`.
  - `requiredEntries` → `["transformer/flux-2-klein-4b-int4.safetensors", "vae/flux-2-vae.safetensors", "qwen3-encoder/model.safetensors", "qwen3-encoder/tokenizer.json", "qwen3-encoder/config.json"]`. Empirical list verified Step 4.
  - `resourcesSubpath` → `""` (empty — FLUX bundle dir IS the resources dir; no nesting like Apple zips).
  - `defaultPrompt` → `"a coloring book page of a fox in a forest, simple bold line art, kid-friendly, clean illustration"` (NO `ColoringBookAF` trigger — Klein's native bias handles this; SDXL-LoRA trigger words are wrong vocabulary for Klein).
  - `defaultNegativePrompt` → `""` (Klein 4B is calibrated for guidance=1.0 → negative prompt is a no-op; surfacing it in UI is harmless but engine ignores it).

  Add new `EngineKind` computed property:
  ```swift
  public var engineKind: EngineKind {
      switch self {
      case .palettized, .base, .iosSplitEinsum, .loraColoring:
          return .coreMLSDXL
      case .fluxKlein:
          return .mlxFlux
      }
  }
  ```

  Add new `downloadItems` extension (the multi-file shape from §2). Existing SDXL variants get a 1-item shim wrapping their existing `downloadURL` + `sha256` + `expectedSizeBytes`; `.fluxKlein` returns the 3-item array (+ small tokenizer JSON files = ~5 items total).

  Add new `engineHint` (Settings UI copy helper):
  ```swift
  public var engineHint: String {
      switch self {
      case .palettized: return "Apple SDXL Base — genel amaçlı."
      case .loraColoring: return "ColoringBookRedmond-V2 LoRA fine-tuned SDXL — trigger 'ColoringBookAF', ~3 GB."
      case .fluxKlein:
          return "FLUX.2 Klein 4B (Apple Silicon MLX) — çocuk boyama estetiği için en güçlü; "
               + "DALL-E seviyesinde değil, SDXL'den belirgin daha iyi. ~35 sn üretim, ~11 GB indirme. "
               + "macOS Sequoia (15.0+) ve 16 GB+ RAM gerekli."
      case .base, .iosSplitEinsum:
          return ""
      }
  }
  ```

**Files touched (MODIFIED):**
- `Tests/ImagingCoreTests/SDXLModelCatalogTests.swift` (~+90 LOC):
  - `test_fluxKlein_isInAllCases`
  - `test_fluxKlein_engineKind_isMlxFlux`
  - `test_palettized_engineKind_isCoreMLSDXL` (regression guard: existing variants stay on Core ML)
  - `test_loraColoring_engineKind_isCoreMLSDXL`
  - `test_fluxKlein_downloadItems_has3PlusItems`
  - `test_fluxKlein_downloadItems_pathsAreUnique`
  - `test_palettized_downloadItems_returnsSingleItemShim` (backward compat: single-file variants still work via the new array API)
  - `test_fluxKlein_resourcesSubpath_isEmpty` (FLUX bundle has no Apple-style nesting)
  - `test_fluxKlein_defaultPrompt_doesNotContainSDXLTrigger` (regression guard — operator hand-tuned per-variant defaults must not bleed across variants)
  - `test_fluxKlein_humanLabel_marksExperimental`
  - `test_defaultVariant_stillPalettized` (existing test, still must pass — FLUX is opt-in; locked decision #10)
  - `test_engineHint_fluxKlein_mentions11GB` (UI copy lock: "~11 GB" must surface)

**LOC delta:** +120 source, +90 test = +210.

**Verification:** `swift test --filter SDXLModelCatalogTests` GREEN with new tests added; existing 7 LoRA tests not regressed.

**Dependency:** Step 0.

**P0.90 5-layer coverage:**
- **Code:** SDXLModelCatalog.swift extension
- **Test:** 12 new XCTestCase methods
- **Substrate:** doc comment on `.fluxKlein` cites this plan + spike artifact path + locked decision table
- **Observability:** `versionMarker` contains `mlx-swift-2.1.0-qwen3-4bit-2026-05` — every launch's installed-marker readback exposes which integration was active
- **Living check:** `test_defaultVariant_stillPalettized` regression guard (no silent flip)

---

### Step 2: GenerationEngineFactory dispatch (~0.5 day)

**Goal:** Engine-agnostic factory + thread it through `GenerationViewModel.start()`.

**Files touched (NEW):**
- `Sources/ImagingCore/Generation/GenerationEngineFactory.swift` (~+60 LOC):
  ```swift
  import Foundation

  /// Engine dispatch — returns the right runtime for a variant's engine kind.
  /// Phase A.4 introduces multi-engine support; FLUX variant lives in a
  /// separate target (`FluxEngine`) to keep MLX deps out of the CoreML target.
  ///
  /// Why a factory not a switch inside GenerationViewModel:
  ///   - Centralizes the engine surface so future variants (Phase B FLUX dev,
  ///     Phase C cloud) extend ONE switch, not every callsite.
  ///   - Keeps engine types behind `any GenerationEngine` existential — VM
  ///     doesn't import CoreMLEngine OR FluxEngine, only ImagingCore.
  ///
  /// NOTE: This file lives in ImagingCore but the concrete engines live in
  /// CoreMLEngine + FluxEngine. To avoid circular deps, the factory is a
  /// thin re-export: callers (AppShell) import all three modules and use the
  /// factory's static method which is conditionally compiled based on
  /// available engines. For v0.6.0.0 a simpler approach: factory lives in
  /// AppShell, since AppShell already imports both engine modules.
  ```

  **Re-decision:** Move the factory to AppShell, not ImagingCore (the circular-dep avoidance pattern above):
  - `Sources/AppShell/GenerationEngineFactory.swift` (~+60 LOC):
    ```swift
    import Foundation
    import ImagingCore
    import CoreMLEngine
    import FluxEngine

    @MainActor
    public enum GenerationEngineFactory {
        public static func engine(for variant: SDXLModelCatalog.Variant) -> any GenerationEngine {
            switch variant.engineKind {
            case .coreMLSDXL:
                return StableDiffusionCoreMLEngine(modelBundleURL: nil)
            case .mlxFlux:
                return Flux2KleinEngine()
            }
        }
    }
    ```

**Files touched (MODIFIED):**
- `Sources/AppShell/ViewModels/GenerationViewModel.swift` (~+15 LOC, ~5 LOC changed):
  ```swift
  // OLD: let engine = StableDiffusionCoreMLEngine()
  // NEW:
  let variant = SettingsStore.shared.sdxlModelVariantTyped
  let engine = GenerationEngineFactory.engine(for: variant)
  engineName = engine.engineName + " / " + variant.rawValue
  ```

**Files touched (NEW):**
- `Tests/AppShellTests/GenerationEngineFactoryTests.swift` — IF AppShellTests target doesn't exist, defer the test to Step 4 (smoke). The factory is trivial enough that the integration smoke test from Step 9 covers correctness without a dedicated unit test. **Decision: skip a separate factory test file** to avoid bootstrapping AppShellTests target solely for this. Factory is tested indirectly by smoke #1 (palettized variant generates → CoreML engine selected) and smoke #5 (FLUX variant generates → MLX engine selected).

**LOC delta:** +60 factory, +15 VM = +75. No new tests this step (covered by smoke).

**Verification:**
- `swift build` GREEN (FluxEngine target still empty but factory references `Flux2KleinEngine()` — Step 4 creates that type. So Step 2 either (a) lands AFTER Step 4, OR (b) lands with a stub `Flux2KleinEngine`).
- **Re-order:** push Step 2 (factory + VM wire) to AFTER Step 4 (engine implementation) — see revised dependency graph at end of §3.

**Dependency:** Step 4 (must exist before factory references it).

**P0.90 5-layer coverage:**
- **Code:** GenerationEngineFactory.swift + GenerationViewModel.swift change
- **Test:** indirect via Step 9 smoke checklist (#1 + #5)
- **Substrate:** factory file header explains "Why AppShell not ImagingCore" decision
- **Observability:** `engineName` log line carries variant tag (`"core-ml-sdxl / palettized"` vs `"flux2-klein / fluxKlein"`)
- **Living check:** smoke #1 + #5

---

### Step 3: Multi-file ModelDownloadManager refactor (~1 day)

**Goal:** Extend `ModelDownloadManager` from single-zip-per-variant to multi-file-per-variant. Existing SDXL variants continue to use the single-zip path; FLUX uses the multi-file path.

**Files touched (MODIFIED):**
- `Sources/ImagingCore/Generation/ModelDownloadManager.swift` (~+180 LOC, ~30 LOC changed):

  **New internal multi-file download orchestrator** (no public API change for SDXL callers):
  ```swift
  private func startMultiFileDownload(for variant: SDXLModelCatalog.Variant) async {
      let items = variant.downloadItems
      var aggregateBytes: Int64 = 0
      let aggregateTotal = items.map(\.sizeBytes).reduce(0, +)

      setPhase(.downloading(bytesWritten: 0, totalBytes: aggregateTotal,
                            throughputBytesPerSec: nil, etaSeconds: nil),
               for: variant)

      let bundleDir = bundleDirectory(for: variant)
      try? FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

      for (index, item) in items.enumerated() {
          // Track per-item bytes; aggregate progress emits sum
          let downloader = ModelDownloader(url: item.downloadURL) { [weak self] event in
              Task { @MainActor [weak self] in
                  guard let self else { return }
                  switch event {
                  case .progress(let bytes, _, let throughput, _):
                      let total = aggregateTotal
                      let agg = aggregateBytes + bytes
                      let etaSec: Int? = {
                          guard let tp = throughput, tp > 0 else { return nil }
                          let remaining = max(0, total - agg)
                          return min(99 * 60, Int(Double(remaining) / tp))
                      }()
                      self.setPhase(.downloading(bytesWritten: agg, totalBytes: total,
                                                 throughputBytesPerSec: throughput,
                                                 etaSeconds: etaSec),
                                    for: variant)
                  case .finished(let tempFileURL):
                      // Move file into per-item relativePath under bundleDir
                      let dest = bundleDir.appendingPathComponent(item.relativePath)
                      try? FileManager.default.createDirectory(
                          at: dest.deletingLastPathComponent(),
                          withIntermediateDirectories: true)
                      try? FileManager.default.removeItem(at: dest)
                      try? FileManager.default.moveItem(at: tempFileURL, to: dest)
                      // Per-item SHA verify (after move, on final path)
                      if let expectedSHA = item.sha256 {
                          let actual = try? Self.streamingSHA256(of: dest)
                          if actual?.lowercased() != expectedSHA.lowercased() {
                              self.setPhase(.failed(message: "SHA256 uyumsuz: \(item.relativePath)"),
                                            for: variant)
                              return
                          }
                      }
                      aggregateBytes += item.sizeBytes
                      // Continue to next item — loop driver awaits sequentially
                  case .cancelled:
                      self.setPhase(.idle, for: variant); return
                  case .failed(let message):
                      self.setPhase(.failed(message: "\(item.relativePath): \(message)"), for: variant)
                      return
                  }
              }
          }
          await downloader.startAndAwait()   // NEW helper — awaits .finished/.failed/.cancelled
      }

      // All items done; verify structural completeness
      let trulyInstalled = isInstalled(for: variant)
      if trulyInstalled {
          try? variant.versionMarker.write(
              to: bundleDir.appendingPathComponent(".sdxl-version"),
              atomically: true, encoding: .utf8)
          setPhase(.ready, for: variant)
      } else {
          setPhase(.failed(message: "İndirme tamamlandı ama beklenen dosyalar bulunamadı — bundle yapısı değişmiş olabilir."),
                   for: variant)
      }
  }

  // Dispatch in startDownload(for:)
  public func startDownload(for variant: SDXLModelCatalog.Variant) async {
      // ... existing idempotency / already-installed short-circuit ...
      switch variant.engineKind {
      case .coreMLSDXL:
          await startSingleFileDownload(for: variant)   // existing zip flow renamed
      case .mlxFlux:
          await startMultiFileDownload(for: variant)
      }
  }
  ```

  **`ModelDownloader.startAndAwait()` extension** — Phase A.3's `ModelDownloader` is callback-based; add an async wrapper that completes on terminal events (.finished, .failed, .cancelled). ~30 LOC in `Sources/ImagingCore/Generation/ModelDownloader.swift`.

  **`Self.streamingSHA256(of:)`** — extract the SHA helper from `ArchiveExtractor` (currently does SHA over zip stream); promote to a top-level helper or duplicate the streaming hash logic for arbitrary files. ~25 LOC.

  **`isInstalled(for:)` already iterates `requiredEntries`** — no change needed for FLUX; the FLUX `requiredEntries` array from Step 1 lists the 5 final relative paths under `bundleDir`, so the existing presence-check logic works as-is. (This is why Step 1's `requiredEntries` design uses full relative paths like `"transformer/flux-2-klein-4b-int4.safetensors"`, not bare filenames.)

  **Subdir mapping extension (`subdirName`):**
  ```swift
  private static func subdirName(for variant: SDXLModelCatalog.Variant) -> String {
      switch variant {
      case .palettized:     return "sdxl"             // legacy
      case .base:           return "sdxl-base"
      case .iosSplitEinsum: return "sdxl-ios"
      case .loraColoring:   return "sdxl-lora-coloring"
      case .fluxKlein:      return "flux-klein-4b"    // NEW
      }
  }
  ```

  **Disk-space pre-check** — Phase A.3 backlog item now mandatory for FLUX (~11 GB):
  ```swift
  private func diskSpaceAvailable(at url: URL) -> Int64 {
      guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let available = values.volumeAvailableCapacityForImportantUsage else { return 0 }
      return available
  }

  // Inside startDownload:
  let required = variant.expectedSizeBytes + 2_000_000_000   // 2 GB extraction headroom
  let available = diskSpaceAvailable(at: Self.modelsRootDirectory)
  if available < required {
      setPhase(.failed(message: "Yetersiz disk alanı (\(available / 1_000_000_000) GB var, en az \(required / 1_000_000_000) GB gerekli)."),
               for: variant)
      return
  }
  ```

**Files touched (MODIFIED):**
- `Sources/ImagingCore/Generation/ArchiveExtractor.swift` — if streaming SHA helper is extracted, ~10 LOC refactor. Otherwise no change.
- `Sources/ImagingCore/Generation/ModelDownloader.swift` — add `startAndAwait()` async wrapper. ~30 LOC.

**Files touched (NEW):**
- `Tests/ImagingCoreTests/ModelDownloadManagerMultiFileTests.swift` (~+200 LOC):
  - `test_fluxKlein_subdirName_isFluxKlein4b`
  - `test_fluxKlein_bundleDirectory_isolatedFromSDXL` (palettized + fluxKlein paths don't collide)
  - `test_fluxKlein_isInstalled_falseWhenAnyRequiredEntryMissing` (write 4 of 5 → expect false)
  - `test_fluxKlein_isInstalled_trueWhenAllPresentAndMarkerMatches`
  - `test_aggregateProgress_sumsBytesAcrossItems` (mock downloader emits 100 MB on item 1, manager exposes 100 MB; then 200 MB on item 2, manager exposes 300 MB)
  - `test_partialFailure_setsFailedPhaseWithItemPath` (mock item 2 fails → phase.failed message contains item 2's relativePath)
  - `test_resumeAfterCancel_redownloadsFromScratch` (acceptable for v0.6.0.0 — per-item resumeData is a v0.6.x polish)
  - `test_diskSpacePrecheck_failsCleanly_whenInsufficient` (mock low-space env → setPhase(.failed) before any HTTP request)
  - `test_legacyPalettizedDownload_stillUsesSingleFilePath` (regression guard: SDXL flow not touched by multi-file refactor)
  - `test_versionMarker_writtenOnlyAfterAllItemsVerify` (mock SHA mismatch on item 3 → marker file absent on disk)

**LOC delta:** +180 manager, +30 downloader, +25 helper, +200 test = +435.

**Verification:**
- `swift test --filter ModelDownloadManagerMultiFileTests` GREEN (10 tests).
- `swift test --filter ModelDownloadManagerTests` (Phase A.3's existing 9 tests) still GREEN — regression guard.
- Manual: pretend `.fluxKlein` is installed (mkdir + touch 5 expected files + write marker), launch app, observe `isInstalled(for: .fluxKlein) == true`.

**Dependency:** Step 1.

**P0.90 5-layer coverage:**
- **Code:** ModelDownloadManager.swift extension + ModelDownloader.swift wrapper
- **Test:** new 10-test file + 9 Phase A.3 tests preserved
- **Substrate:** multi-file path doc comment cites `wisdom-NEW-candidate: multi-file-download-aggregate-progress-pattern` for Phase A.5 harvest
- **Observability:** each `setPhase(.downloading)` carries item-level path in the message during transitions; `os_log` line includes `variant=fluxKlein item=transformer/...`
- **Living check:** `test_legacyPalettizedDownload_stillUsesSingleFilePath` is the regression guard

---

### Step 4: Flux2KleinEngine implementation (~1.5 days)

**Goal:** Implement `Flux2KleinEngine: GenerationEngine` wrapping `flux-2-swift-mlx` pipeline. Verify on operator's M4 Pro with a 1-step smoke generation.

**Pre-step: source reconnaissance** (the spike used the prebuilt `Flux2CLI` binary; for a library integration we need the underlying API):
1. Clone `https://github.com/VincentGourbin/flux-2-swift-mlx` locally to reference (read-only — don't add to repo).
2. Identify the primary generation entry point. Likely `Flux2Pipeline.generate(prompt:negativePrompt:steps:guidance:seed:width:height:)` returning a `CGImage` or `[CGImage]` (verify the exact signature in the library's SwiftDoc).
3. Identify how the pipeline resolves the model bundle path (likely `init(modelDirectory: URL)` or env var). Verify metallib discovery API (likely `MLX.setMetalLibraryPath` or auto-resolution from `Bundle.module`).

**Files touched (NEW):**
- `Sources/FluxEngine/Flux2KleinEngine.swift` (~+200 LOC):
  ```swift
  import Foundation
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers
  import ImagingCore
  import Flux2Core
  import FluxTextEncoders

  /// FLUX.2 Klein 4B engine — Apple Silicon MLX inference via flux-2-swift-mlx.
  ///
  /// Phase A.4 third user-selectable engine variant. Bundle lives at
  /// ModelDownloadManager.resourcesDirectory(for: .fluxKlein) which holds:
  ///   transformer/flux-2-klein-4b-int4.safetensors
  ///   vae/flux-2-vae.safetensors
  ///   qwen3-encoder/{model.safetensors,tokenizer.json,config.json}
  ///
  /// Runtime requirements:
  ///   - macOS 15+ (Sequoia)
  ///   - Apple Silicon (M1+); int4 quant fits in 16 GB RAM but tight
  ///   - mlx.metallib bundled in this target's Resources (see Bundle.module)
  ///
  /// Defaults (Klein-calibrated, do not expose in v0.6.0.0 UI per locked decision #6):
  ///   - steps: 4 (Klein is distilled — 4-step matches dev's 28-step quality at its tier)
  ///   - guidance: 1.0 (Klein expects no CFG; >1.0 produces over-saturation)
  ///   - 1024×1024 only (other sizes need transformer reconfig)
  public struct Flux2KleinEngine: GenerationEngine {
      public let engineName: String = "flux2-klein"
      public let supportedModels: [String] = ["fluxKlein"]

      public init() {
          // One-shot metallib path setup (idempotent — MLX framework caches)
          Self.ensureMetallibResolved()
      }

      private static var metallibInitialized = false
      private static let metallibLock = NSLock()

      private static func ensureMetallibResolved() {
          metallibLock.lock(); defer { metallibLock.unlock() }
          guard !metallibInitialized else { return }
          if let metallibURL = Bundle.module.url(forResource: "mlx", withExtension: "metallib") {
              // Set env var the MLX framework reads at first dispatch
              setenv("MLX_METAL_LIBRARY_PATH", metallibURL.path, 1)
              metallibInitialized = true
          }
          // If metallib missing: don't crash here; let pipeline init surface the
          // error so the user gets actionable engine-load failure message.
      }

      public func probe() async throws -> EngineHealth {
          let (installed, version) = await MainActor.run {
              let v = SDXLModelCatalog.Variant.fluxKlein
              return (
                  ModelDownloadManager.shared.isInstalled(for: v),
                  v.versionMarker
              )
          }
          let metallibPresent = Bundle.module.url(forResource: "mlx", withExtension: "metallib") != nil
          return EngineHealth(
              isAvailable: installed && metallibPresent,
              version: installed ? version : "model-not-installed",
              detectedDevice: metallibPresent ? "Apple Silicon GPU (MLX)" : "metallib-missing"
          )
      }

      public func generate(request: GenerationRequest) -> AsyncThrowingStream<GenerationProgress, Error> {
          return AsyncThrowingStream { continuation in
              Task.detached {
                  continuation.yield(.started)

                  let (installed, bundleURL) = await MainActor.run {
                      let v = SDXLModelCatalog.Variant.fluxKlein
                      return (
                          ModelDownloadManager.shared.isInstalled(for: v),
                          ModelDownloadManager.shared.resourcesDirectory(for: v)
                      )
                  }
                  guard installed else {
                      let err = GenerationError.modelNotInstalled
                      continuation.yield(.failed(err))
                      continuation.finish(throwing: err)
                      return
                  }

                  do {
                      let result = try Self.runInference(
                          request: request,
                          bundleURL: bundleURL,
                          progressEmit: { step, total in
                              continuation.yield(.step(current: step, total: total))
                          }
                      )
                      continuation.yield(.completed(result))
                      continuation.finish()
                  } catch is CancellationError {
                      let err = GenerationError.inferenceFailed("Cancelled")
                      continuation.yield(.failed(err))
                      continuation.finish(throwing: err)
                  } catch let e as GenerationError {
                      continuation.yield(.failed(e))
                      continuation.finish(throwing: e)
                  } catch {
                      let err = GenerationError.inferenceFailed(error.localizedDescription)
                      continuation.yield(.failed(err))
                      continuation.finish(throwing: err)
                  }
              }
          }
      }

      private static func runInference(
          request: GenerationRequest,
          bundleURL: URL,
          progressEmit: @escaping (Int, Int) -> Void
      ) throws -> GenerationResult {
          let startedAt = Date()

          // Map our GenerationRequest → flux-2-swift-mlx config
          // EXACT API surface to be verified at integration time. Below is the
          // expected shape based on the library's Flux2App example code.
          let config = Flux2GenerationConfiguration(
              prompt: request.prompt,
              negativePrompt: "",            // Klein 4B: guidance=1.0, negative prompt is no-op
              numInferenceSteps: 4,           // Klein default; ignore request.steps for v0.6.0.0
              guidanceScale: 1.0,             // Klein default; ignore request.cfgScale for v0.6.0.0
              width: 1024,                    // Klein bundle is calibrated for 1024 only
              height: 1024,
              seed: UInt64(request.seed)
          )

          let pipeline: Flux2Pipeline
          do {
              pipeline = try Flux2Pipeline(modelDirectory: bundleURL)
          } catch {
              throw GenerationError.modelLoadFailed("Flux2 pipeline init: \(error.localizedDescription)")
          }

          let cgImage: CGImage
          do {
              cgImage = try pipeline.generate(configuration: config) { step in
                  if Task.isCancelled { return false }
                  progressEmit(step + 1, config.numInferenceSteps)
                  return true
              }
          } catch {
              throw GenerationError.inferenceFailed(error.localizedDescription)
          }

          let outputURL = try writePNG(cgImage: cgImage, request: request)
          let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
          return GenerationResult(
              outputURL: outputURL,
              seed: request.seed,
              durationMs: durationMs,
              engineName: "flux2-klein"
          )
      }

      // Output helpers — copy of SDXL engine's writePNG / defaultOutputDirectory /
      // generatedFileName but with "flux2-klein-" prefix on filenames. ~30 LOC.
      // ... (omitted for plan brevity; mirror StableDiffusionCoreMLEngine.swift)
  }
  ```

  **CRITICAL caveat** for MAX during execution: the exact `Flux2Pipeline` / `Flux2GenerationConfiguration` API names + signatures are inferred from the library's general shape. MAX must, as a first execution sub-step, clone the upstream repo and read the actual public surface, then adjust this skeleton. Allocate 1h in Step 4 for API alignment.

**Files touched (NEW):**
- `Tests/FluxEngineTests/Flux2KleinEngineSmokeTests.swift` (~+80 LOC):
  - `test_probe_returnsUnavailable_whenBundleMissing`
  - `test_probe_metallibPresentInBundle` (assertion against `Bundle.module.url(forResource: "mlx", withExtension: "metallib")` — passes only after Step 5 metallib copy)
  - `test_smokeGenerate_realInference_oneStep` — gated `XCTSkipUnless(await MainActor.run { ModelDownloadManager.shared.isInstalled(for: .fluxKlein) })`. Generate with steps=1 (Klein's minimum); assert output PNG written + size >50 KB. ~45-second test runtime on M4 Pro; only runs when bundle is installed.

**LOC delta:** +200 engine, +80 test = +280.

**Verification:**
- `swift build` GREEN — confirms `Flux2Core` + `FluxTextEncoders` imports resolve.
- `swift test --filter Flux2KleinEngineSmokeTests` GREEN (probe tests always; smoke test XCTSkip unless bundle present on operator's box).
- **Manual operator step:** copy spike's already-downloaded model files into `~/Library/Application Support/GenesisImaging/models/flux-klein-4b/<correct paths>` + write marker file. Re-run smoke test → expect real inference + output PNG.

**Dependency:** Steps 0, 1, 3, 5 (needs metallib bundled).

**Risk:** flux-2-swift-mlx API may have changed between 2.1.0 release and PR #85 (merged 2026-05-17 per operator context). Pin holds at 2.1.0 exact → known surface. If 2.1.0 has a critical bug fixed only in main, fork the repo to a pinned commit on our org and depend via SPM URL. Budget 4h contingency.

**P0.90 5-layer coverage:**
- **Code:** Flux2KleinEngine.swift
- **Test:** 3 new tests (1 always-on, 2 gated)
- **Substrate:** engine file header cites locked decisions #1, #6, #7 + spike artifact paths
- **Observability:** `engineName = "flux2-klein"` propagates to `GenerationResult.engineName` → history entries are engine-tagged
- **Living check:** `test_probe_metallibPresentInBundle` regression guard (catches metallib accidentally removed from Resources during a future cleanup)

---

### Step 5: Metallib bundling (~0.5 day)

**Goal:** `mlx.metallib` shipped inside `Sources/FluxEngine/Resources/` so the customer DMG has zero-setup MLX runtime.

**Files touched (NEW):**
- `scripts/copy-mlx-metallib.sh` (~50 LOC):
  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  # Copies mlx.metallib from the SPM checkout of mlx-swift into the FluxEngine
  # target's Resources directory. Run after `swift package resolve` (which
  # populates .build/checkouts/mlx-swift/).
  REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  DEST="${REPO_ROOT}/Sources/FluxEngine/Resources/mlx.metallib"
  CHECKOUT_PATTERN="${REPO_ROOT}/.build/checkouts/mlx-swift/Source/Cmlx/mlx/backend/metal/kernels/mlx.metallib"
  # Fallback: prebuilt metallib path (varies by mlx-swift version)
  FALLBACK="/opt/homebrew/lib/mlx.metallib"

  if [[ -f "$CHECKOUT_PATTERN" ]]; then
      cp -f "$CHECKOUT_PATTERN" "$DEST"
      echo "Copied from SPM checkout: $CHECKOUT_PATTERN"
  elif [[ -f "$FALLBACK" ]]; then
      cp -f "$FALLBACK" "$DEST"
      echo "Copied from Homebrew fallback: $FALLBACK"
  else
      echo "ERROR: mlx.metallib not found at $CHECKOUT_PATTERN or $FALLBACK" >&2
      exit 1
  fi
  ls -la "$DEST"
  shasum -a 256 "$DEST"
  ```

- `Sources/FluxEngine/Resources/mlx.metallib` — committed binary (~10-50 MB). Acceptable git LFS or direct commit; **decision: direct commit** (no LFS dep added) since metallib is small relative to other repo binaries and changes only when MLX-Swift version bumps.

**Files touched (MODIFIED):**
- `Package.swift` — already declared `resources: [.copy("Resources/mlx.metallib")]` in Step 0; no further change.
- `scripts/build.sh` (existing release script) — prepend `./scripts/copy-mlx-metallib.sh` to ensure fresh metallib before each build. ~3 LOC change.
- `.gitattributes` (NEW or modified) — mark metallib as binary: `Sources/FluxEngine/Resources/mlx.metallib binary`. Prevents git from line-ending munging.

**Verification:**
1. `./scripts/copy-mlx-metallib.sh` → expect "Copied from..." log + `ls -la` showing metallib size.
2. `swift build` → SPM copies the resource into `.build/.../FluxEngine_FluxEngine.bundle/`.
3. Build the app DMG via `./scripts/package-app.sh`; inspect with `pkgutil --files GenesisImaging.app | grep metallib` — expect path under `Contents/Resources/FluxEngine_FluxEngine.bundle/`.
4. Open the .app; check Console.app for any MLX runtime errors during a smoke generation.
5. **Codesign verification:** `codesign --verify --deep --strict GenesisImaging.app` → expect "valid on disk". If sparkle-inside-out-resign breaks (Phase A.2 had related lessons), patch `scripts/deep-resign.sh` to include the metallib path.

**Dependency:** Step 0 (SPM resource declaration).

**Risk:** metallib version skew — if a customer's mlx-swift transitive dep version bumps independently, the runtime may expect a different metallib ABI. Mitigation: we ship the metallib that ships with our exact-pinned flux-2-swift-mlx 2.1.0's transitive mlx-swift version. Locking flux-2-swift-mlx at exact 2.1.0 locks the metallib ABI transitively.

**P0.90 5-layer coverage:**
- **Code:** copy-mlx-metallib.sh, Sources/FluxEngine/Resources/mlx.metallib, .gitattributes
- **Test:** `test_probe_metallibPresentInBundle` from Step 4
- **Substrate:** script header documents the bundle-vs-Homebrew failover; `wisdom-NEW-candidate: mlx-metallib-bundling-codesign-discipline`
- **Observability:** SHA256 of metallib logged during `copy-mlx-metallib.sh`; archive to `docs/proofs/imaging-a4-flux-klein/metallib-sha.txt`
- **Living check:** `codesign --verify` step in release script + manual smoke on signed DMG before ship

---

### Step 6: Settings UI variant picker extension (~0.5 day)

**Goal:** Settings shows 3 variants in the picker; per-variant status row for fluxKlein; aggregate multi-file progress display.

**Files touched (MODIFIED):**
- `Sources/AppShell/Views/SettingsView.swift` (~+100 LOC, ~10 LOC changed):

  **Picker:** Phase A.3 already shows palettized + loraColoring. Add fluxKlein as third tag, gated on macOS 15 + Apple Silicon (informational only — picker still shows it but Settings warning copy fires if env fails):
  ```swift
  Picker("Model Varyantı", selection: $settings.sdxlModelVariantId) {
      Text("Apple Base SDXL (~6.7 GB)").tag(SDXLModelCatalog.Variant.palettized.rawValue)
      Text("Çocuk Boyama Kitabı LoRA (~3 GB)").tag(SDXLModelCatalog.Variant.loraColoring.rawValue)
      Text("FLUX.2 Klein (deneysel, ~11 GB)").tag(SDXLModelCatalog.Variant.fluxKlein.rawValue)
  }
  .pickerStyle(.menu)
  ```

  **Variant status section grows:**
  ```swift
  Section("Görüntü Oluşturma — Model Varyantları") {
      variantStatusRow(.palettized)
      Divider()
      variantStatusRow(.loraColoring)
      Divider()
      variantStatusRow(.fluxKlein)
  }
  ```

  **Aggregate progress UI for fluxKlein** — `downloadingRow` already shows bytes/total/throughput/eta for single-file. For multi-file, the existing UI works because `phase.downloading` carries aggregate bytes from Step 3's refactor. Optional v0.6.x polish: add "dosya 2/5" sub-label by extending Phase with `currentItemIndex`/`totalItems` (deferred; not blocker).

  **macOS 15 + Apple Silicon precheck banner:** when `settings.sdxlModelVariant == .fluxKlein`:
  ```swift
  if !ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 15, minorVersion: 0, patchVersion: 0)) {
      Text("FLUX.2 Klein için macOS Sequoia (15.0+) gerekli — bu sistem desteklenmiyor.")
          .foregroundStyle(.orange)
  }
  // Apple Silicon check: #if arch(arm64) at compile time; runtime check via uname
  ```

**Verification:**
- Build, open Settings → picker shows 3 options. Select fluxKlein → status row appears with İndir CTA and "~11 GB" hint.
- macOS 14 (if testable VM available) → warning banner appears.
- Tap İndir → progress UI advances; aggregate bytes display correctly through 5 file downloads.

**Dependency:** Steps 1, 3.

**P0.90 5-layer coverage:**
- **Code:** SettingsView.swift extension
- **Test:** manual smoke (Step 9 #2, #3)
- **Substrate:** picker copy + warning text are operator-locked strings; SettingsView code comment cites this plan §1 honest-positioning anchor
- **Observability:** picker selection persists to UserDefaults → `defaults read ai.softwareasan.imaging sdxlModelVariantId` exposes current state
- **Living check:** none beyond smoke

---

### Step 7: GenerateView variant-aware defaults wire (~0.25 day)

**Goal:** `applyVariantDefaults()` already exists in Phase A.3; verify FLUX defaults are sensible and the banner copy is correct.

**Files touched (MODIFIED):**
- `Sources/AppShell/ViewModels/GenerationViewModel.swift` (~+5 LOC):
  - Existing init reads `variant.defaultPrompt` + `defaultNegativePrompt`. The FLUX-specific defaults from Step 1 (no SDXL trigger; empty negative) propagate automatically.
  - `start()` engine selection uses `GenerationEngineFactory` (Step 2) — already done.

- `Sources/AppShell/Views/GenerateView.swift` (~+25 LOC):
  - Banner copy when fluxKlein variant active + not installed: `"FLUX.2 Klein (~11 GB indirilecek) — Ayarlar'dan başlat"`.
  - Banner copy when fluxKlein active + generating: `"FLUX.2 Klein üretiliyor — adım \(current)/\(total) (~35-45 sn)"`.
  - Variant pill at top-right shows `"flux2-klein"` when active (vs `"core-ml-sdxl"`).

**Verification:**
- Switch to fluxKlein → prompt field shows FLUX default (no `ColoringBookAF` prefix).
- Banner copy matches variant identity.
- Generate FLUX → progress bar advances 1/4 → 2/4 → 3/4 → 4/4 over ~35-45 sec.

**Dependency:** Steps 1, 2, 6.

**P0.90 5-layer coverage:** copy-discipline; manual smoke; covered in Step 9.

---

### Step 8: License + about screen update (~0.25 day)

**Goal:** Compliance — surface FLUX + Qwen3 + mlx-swift + flux-2-swift-mlx licenses in About screen.

**Files touched (MODIFIED):**
- `Sources/AppShell/Views/SettingsView.swift` (Hakkında section, ~+30 LOC):
  ```swift
  Section("Üçüncü Taraf Lisansları") {
      LabeledContent("Apple ml-stable-diffusion", value: "MIT")
      LabeledContent("Sparkle", value: "MIT-style")
      LabeledContent("ColoringBookRedmond-V2 LoRA", value: "OpenRAIL-M (internal-use posture)")
      LabeledContent("FLUX.2 Klein 4B", value: "Apache 2.0 (commercial OK)")
      LabeledContent("Qwen3-4B (MLX-4bit)", value: "Apache 2.0")
      LabeledContent("mlx-swift", value: "MIT")
      LabeledContent("flux-2-swift-mlx", value: "MIT")
      LabeledContent("ncnn (upscale)", value: "BSD-3-Clause")
  }
  ```

**Files touched (NEW):**
- `docs/proofs/imaging-a4-flux-klein/LICENSES.md` — copy/excerpt all third-party licenses for substrate trail. Operator can produce this from each upstream's LICENSE file. ~200 LOC.

**Verification:** Build, open Settings → Hakkında, confirm all 8 rows visible with correct license labels.

**Dependency:** none (cosmetic).

**P0.90 5-layer coverage:** substrate (LICENSES.md) is the load-bearing layer.

---

### Step 9: Tests + smoke + ship gate (~1 day)

**Goal:** Drive `swift test` GREEN; pass 7-item manual smoke; capture proofs.

**11a. Full test pass:**
- Phase A.3 baseline = 207+ GREEN per Phase A.3 plan §11a. Operator's prompt states current is "194 tests GREEN" — likely a sub-pruning happened in Phase A.3 ship or operator's number is pre-A.3. Reconcile in first sub-step: run baseline `swift test 2>&1 | tail -20` and record actual.
- Expected adds from A.4:
  - SDXLModelCatalogTests: +12 (Step 1) → +12
  - ModelDownloadManagerMultiFileTests: +10 (Step 3) → +10
  - Flux2KleinEngineSmokeTests: +3 (1 always + 2 gated) → +1 always-on (gated skip on CI without bundle)
  - **Target: 210+ GREEN with at most 2 XCTSkip on bundle-gated tests.**

**11b. Manual smoke checklist (7 items, operator-runnable on M4 Pro macOS 15.7.5):**

1. **Fresh launch regression:** delete app + Application Support → install new build → variant defaults to `.palettized` → Settings shows 3-variant picker → palettized download flow works (Phase A.2/A.3 regression guard).

2. **Switch to FLUX without install:** Settings → pick fluxKlein → İndir CTA appears with "~11 GB" hint + macOS 15 banner (absent on Sequoia) + Apple Silicon banner (absent on Apple Silicon).

3. **Multi-file FLUX download:** tap İndir → progress UI shows aggregate bytes incrementing correctly across 5 file downloads → SHA verify per item → all items present → marker writes → "Model yüklü" → "Aktif" badge moves to fluxKlein row.

4. **Generate with FLUX active:** open Generate → prompt pre-populated with FLUX default (no SDXL trigger) → tap Üret → progress 1/4 → 2/4 → 3/4 → 4/4 over 35-45 sec → output PNG saved → operator visual screenshot capture.

5. **Variant switch instantaneity:** Settings → palettized ↔ fluxKlein switch is instant (both installed, no re-download) → "Aktif" badge moves correctly → engine pill in Generate view updates.

6. **Disk coexistence:** `du -sh ~/Library/Application\ Support/GenesisImaging/models/` → ~9.7 + ~11 = ~20.7 GB total (all 3 variants installed); Settings shows all 3 as "Model yüklü".

7. **Quality smoke — Nadezhda's canonical 6 prompts:** regenerate the same 6 prompts the spike pack used (`~/Desktop/flux-nadezhda-test/`). Visual diff against spike outputs — expect ≥80% similarity (same seed → near-identical; random seeds → quality match within tolerance). If catastrophic regression (FLUX output looks like SDXL or noise), halt ship; investigate.

**11c. Visual proof capture (P0.45):**
- `docs/proofs/imaging-a4-flux-klein/fox-in-forest-fluxKlein.png` (smoke #4 output)
- `docs/proofs/imaging-a4-flux-klein/nadezhda-6-prompts-fluxKlein/` (6 PNGs from smoke #7)
- `docs/proofs/imaging-a4-flux-klein/pin.json` (copy of multi-file SHA pins from Step 4 spike download)
- `docs/proofs/imaging-a4-flux-klein/metallib-sha.txt` (from Step 5)
- `docs/proofs/imaging-a4-flux-klein/LICENSES.md` (Step 8)
- `docs/proofs/imaging-a4-flux-klein/VERDICT-NADEZHDA-spike.md` (verbatim quote from operator context) + placeholder for `VERDICT-NADEZHDA-shipped.md` (post-v0.6.0.0 update)

**Dependency:** Steps 0-8 all complete.

**P0.90 5-layer coverage:** full matrix (Code + Test + Substrate + Observability + Living Check) summarized in §5.

---

### Step 10: vps.tc + R2 mirror upload (~0.5 day) — BONUS, operator-approved decision #4

**Goal:** Mirror the 3 FLUX assets to apps.softwareasan.ai (gns-gate-01 Caddy) + R2 bucket; catalog gains primary HF URL pin + comment with fallback URLs. Same dual-host pattern as Phase A.3 LoRA bundle.

**Files touched (NEW):**
- `scripts/flux-mirror-upload.sh` (~80 LOC):
  ```bash
  set -euo pipefail
  # Re-uses spike's already-downloaded files (~/Desktop/flux-spike/) — no re-fetch
  SPIKE_DIR="$HOME/Desktop/genesis-imaging/tools/flux-spike"
  TRANSFORMER="$SPIKE_DIR/models/transformer/flux-2-klein-4b-int4.safetensors"
  VAE="$SPIKE_DIR/models/vae/flux-2-vae.safetensors"
  QWEN="$SPIKE_DIR/models/qwen3-encoder/model.safetensors"
  # ... (similar pattern for tokenizer files)

  # 1. scp to gns-gate-01 (Phase A.3 pattern):
  scp "$TRANSFORMER" gns-gate-01:/var/www/softwareasan-models/genesis-imaging-flux/
  scp "$VAE" gns-gate-01:/var/www/softwareasan-models/genesis-imaging-flux/vae/
  scp "$QWEN" gns-gate-01:/var/www/softwareasan-models/genesis-imaging-flux/qwen3-encoder/

  # 2. rclone to R2 (Phase A.3 bucket):
  rclone copy "$TRANSFORMER" r2:software-as-an-ai-models/flux-klein/transformer/
  rclone copy "$VAE" r2:software-as-an-ai-models/flux-klein/vae/
  rclone copy "$QWEN" r2:software-as-an-ai-models/flux-klein/qwen3-encoder/

  # 3. SHA verify each upload (curl -I + Content-Length parity per Phase A.3 lesson)
  # 4. Emit fallback URLs into ./build/flux-fallback-pins.json
  ```

**Files touched (MODIFIED):**
- `Sources/ImagingCore/Generation/SDXLModelCatalog.swift` — add comment block above `.fluxKlein` `downloadItems`:
  ```swift
  // Primary: Hugging Face direct (anonymous-pull OK; verified Step 4 spike)
  // Fallback (manual flip in v0.6.x catalog patch if HF rate-limits surface):
  //   - apps.softwareasan.ai/genesis-imaging-flux/...
  //   - r2:software-as-an-ai-models/flux-klein/...
  // SHA same across all 3 hosts (same file bytes).
  ```
  Catalog stays HF-primary for v0.6.0.0 — mirror is insurance, not flipped by default.

**Verification:** `curl -I` each fallback URL → 200 + matching Content-Length.

**Dependency:** Steps 0-4 (need verified SHAs to mirror).

**P0.90 5-layer coverage:** Living check via R2 pin-drift workflow extension (Phase A.3 pattern).

**If time-budget pressure:** skip this step for v0.6.0.0 and ship HF-only. Document the deferred mirror in handoff for v0.6.0.1 follow-up.

---

### Step 11: Version bump + ship v0.6.0.0 (~0.25 day)

**Goal:** Cut release; Sparkle pickup for Nadezhda.

**Files touched (MODIFIED):**
- `genesis.json`:
  - `version`: `"0.5.0.0"` → `"0.6.0.0"`
  - `platform.min_version`: `"14.0"` → `"15.0"`
  - `phases.faz_2.variants`: add `"fluxKlein"` to existing array (e.g., `["palettized", "loraColoring", "fluxKlein"]`).
  - `phases.faz_2.engines`: NEW field, `["coreML", "mlxFlux"]` — substrate-level engine inventory.
  - `phases.faz_2.notes`: append a 1-line summary "v0.6.0.0 ships FLUX.2 Klein 4B via flux-2-swift-mlx; macOS 15+ required".

- Sparkle appcast (whichever script generates it — likely `scripts/generate-appcast.sh`):
  - v0.6.0.0 entry gets `<sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>`. Sonoma users stay on v0.5.x.
  - Release notes (locked operator copy):
    > **v0.6.0.0 — FLUX.2 Klein 4B**
    > Yeni model varyantı: FLUX.2 Klein (deneysel). Çocuk boyama kitabı için en güçlü on-device varyantımız. SDXL'den belirgin daha iyi, DALL-E seviyesinde değil — bu aşama için yeterli (Nadezhda doğruladı).
    > Gereksinimler: macOS Sequoia (15.0+), Apple Silicon, 16 GB+ RAM, ~11 GB indirme.
    > Ayarlar → Görüntü Oluşturma → Model Varyantı: FLUX.2 Klein seç → İndir.

- `./scripts/version_bump.sh` (existing helper) → v0.5.0.0 → v0.6.0.0
- Git commit + `git tag v0.6.0.0` (signed if existing convention; per Phase A.3)
- `./scripts/build.sh && ./scripts/package-app.sh && ./scripts/generate-appcast.sh` → DMG → notarize → Sparkle appcast push

**Verification:**
- DMG opens on macOS 15.7.5; first launch picks `.palettized` default; switch to fluxKlein → İndir → all 7 smoke items pass on installed app (not just dev build).
- `codesign --verify --deep --strict /Applications/GenesisImaging.app` GREEN.
- Sparkle appcast curl returns the v0.6.0.0 entry with `minimumSystemVersion=15.0`.

**Dependency:** Steps 0-9 (Step 10 optional).

**P0.90 5-layer coverage:**
- **Code:** genesis.json, version bump, appcast
- **Test:** full `swift test` GREEN target 210+
- **Substrate:** handoff file (Step 12) + proofs dir (Step 9)
- **Observability:** Sparkle appcast = ship signal; engineName per-generation = variant trace
- **Living check:** `wisdom-NEW-candidate: macos-major-bump-sparkle-appcast-minimumSystemVersion` harvested post-ship

---

### Step 12: Customer empirical loop (~ongoing, NOT a ship blocker)

**Goal:** Nadezhda gets v0.6.0.0; tests FLUX on real Etsy workflow; verdict feeds Phase A.5 trigger.

**Substeps:**
- Operator pushes Sparkle release notes (Step 11 copy) → Nadezhda's installed v0.5.0.0 picks up update notification on next launch.
- Operator messages Nadezhda separately (Turkish) with quick "FLUX.2 Klein deneme — Ayarlar > Görüntü Oluşturma > FLUX.2 Klein seç > İndir (~11 GB, bir kez)" walkthrough.
- Nadezhda runs 5-10 actual jobs over 1-2 weeks → verdict captured in `docs/proofs/imaging-a4-flux-klein/VERDICT-NADEZHDA-shipped.md`.
- Verdict feeds Phase A.5 trigger condition matrix:
  - **Positive verdict (FLUX = production-ready for her workflow):** Phase A.5 = FLUX LoRA training (her style fine-tune on Klein 4B) OR polish (4-step → 8-step quality bump option, dynamic per-prompt prompts, etc.).
  - **Mid verdict (FLUX = better but still not commercial-grade):** Phase A.5 = pivot back to upscale + eraser core (operator's "Yol C" — research §3); generation deprioritized.
  - **Negative verdict (FLUX = no improvement over SDXL+LoRA for her):** Phase A.5 = honest deprecation of generation as primary feature; Genesis Imaging's value moves to editing pipeline.

**Dependency:** Step 11 ships.

**P0.90 5-layer coverage:** customer-empirical loop IS the living check; substrate captures the verdict.

---

### Revised dependency graph (corrected from initial enumeration)

```
Step 0 (Package.swift, macOS bump)
   │
   ├──→ Step 1 (Catalog + EngineKind + fluxKlein case + downloadItems)
   │       │
   │       ├──→ Step 3 (ModelDownloadManager multi-file)
   │       │       │
   │       │       └──→ Step 4 (Flux2KleinEngine) ←─ Step 5 (metallib)
   │       │                       │
   │       │                       └──→ Step 2 (Factory + VM wire)
   │       │                                  │
   │       │                                  ├──→ Step 6 (SettingsView picker)
   │       │                                  └──→ Step 7 (GenerateView defaults)
   │       │
   │       └──→ Step 8 (About licenses) [no functional deps]
   │
   └─ all of above → Step 9 (Tests + smoke) → [Step 10 mirror bonus] → Step 11 (Ship) → Step 12 (Customer loop)
```

Critical path: 0 → 1 → 3 → 5 → 4 → 2 → 6 → 9 → 11. ~5-7 days realistic with Phase A.3-style customer-empirical compression.

---

## 4. Risks + Mitigations (~80 lines)

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | **flux-2-swift-mlx bus-factor-1** (23 stars, single maintainer) | Med-High | Upstream silence mid-cycle → we own the fork | `.package(..., exact: "2.1.0")` pin. If maintainer disappears before v0.6.x.y patches, fork to operator's GitHub org; budget 1 contingency week (~5 dev-days) for self-maintenance per /tmp/flux-research.md §3 budget line. |
| 2 | **mlx.metallib bundling breaks Sparkle codesign** | Medium | DMG ships unsigned / refuses to launch / Sparkle update fails | Step 5 + 11 includes `codesign --verify --deep --strict` gate before tag push. If broken, patch `scripts/deep-resign.sh` (Phase A.2 deep-resign exists) to include metallib path explicitly. v0.6.0.1 hotfix path ready. |
| 3 | **macOS 14 (Sonoma) users shut out** | High (by design) | Existing v0.5.x customers on Sonoma stuck unless they upgrade OS | Sparkle appcast `<minimumSystemVersion>15.0</minimumSystemVersion>` keeps Sonoma on v0.5.x indefinitely. Settings copy when FLUX selected: "macOS Sequoia (15.0+) gerekli". Nadezhda confirmed on 15.x — primary customer unaffected. |
| 4 | **Multi-file download partial failure** (item 3 fails after items 1+2 succeed) | Medium | User must restart entire 11 GB download | v0.6.0.0 behavior: failure restarts from scratch. v0.6.x polish: per-item resumeData via URLSession (existing `ModelDownloader` already supports per-file resumeData; just extend to iterate). |
| 5 | **FLUX bundle 11 GB user disk pressure** | Medium | Customer disk-full → bundle install fails mid-way | Step 3 pre-check: `diskSpaceAvailable() < expectedSizeBytes + 2GB headroom` → fail with actionable message before any HTTP request. |
| 6 | **flux-2-swift-mlx API changes between 2.1.0 and master** (PR #85 merged 2026-05-17 = same day as spike) | Medium | Engine init fails if we accidentally drift off 2.1.0 | Exact-pin holds. If a critical bug surfaces only-in-master, document the option to fork-at-commit-SHA in the catalog file header. |
| 7 | **Qwen3 text encoder auto-downloaded at first inference by flux-2-swift-mlx** | Low-Medium | Customer sees "~3 GB extra" surprise download after first Üret tap | Step 1's `requiredEntries` includes Qwen3 paths → ModelDownloadManager downloads them as part of the initial 11 GB. flux-2-swift-mlx config points at the bundle path → no auto-download. Verify in Step 4 smoke. |
| 8 | **macOS app size > 200 MB after metallib bundle** | Low | DMG growth; perception threshold | mlx.metallib is 10-50 MB; current DMG is ~150 MB; new total ~180-200 MB. Acceptable per operator's threshold; capture in proofs/app-size.txt. |
| 9 | **Inference fails on 16 GB Mac** (Klein 4B int4 fits but tight) | Medium | Customer crash / OOM during inference | Settings copy: "16 GB+ RAM gerekli". Engine returns `GenerationError.modelLoadFailed("RAM insufficient")` if pipeline init fails with memory error. Nadezhda's machine spec verified at 16+ GB. |
| 10 | **Cancellation mid-generation hangs MLX dispatch** | Low-Med | UI shows cancelled but GPU still running | Step 4 honors `Task.isCancelled` in step callback; if flux-2-swift-mlx's per-step return false doesn't actually interrupt MLX kernel, the next step boundary catches it. Worst case: 1 step ~10 sec extra; acceptable. |
| 11 | **R2 / Apache 2.0 license interpretation for FLUX VAE** | Low | If VAE has a different license than transformer, commercial-distribution claim weakens | Step 4 verify VAE LICENSE file in HF repo; document in Step 8 LICENSES.md. Klein 4B repo is monolithic Apache 2.0 per locked decision #5; high confidence. |
| 12 | **Substrate-blind plan errors compound** (no wisdom DB available) | Already realized | Possible missed lessons | This plan cites inferred wisdom IDs at each step; MAX must apply `track_wisdom_applied` manually in main session (Phase A.2 + A.3 handoff lesson). Two plans in a row flagged this — operator escalate to substrate-team. |

---

## 5. P0.90 5-Layer Coverage Matrix (~50 lines)

| Step | Code | Test | Substrate | Observability | Living Check |
|---|---|---|---|---|---|
| 0 — macOS+dep | Package.swift, FluxEngine target stub | 194 baseline GREEN preserved | commit msg cites locked decision #1, #2; `wisdom-NEW-candidate: bus-factor-1-dep-pin-exact` | `swift package show-dependencies` → `docs/proofs/imaging-a4-flux-klein/dep-tree.txt` | manual `swift build` gate; CI workflow if exists |
| 1 — Catalog | SDXLModelCatalog.swift +120 LOC | SDXLModelCatalogTests +12 tests | doc comment on `.fluxKlein` cites plan + spike artifact + locked decisions table | `versionMarker` carries `mlx-swift-2.1.0-qwen3-4bit-2026-05` → log on every launch | `test_defaultVariant_stillPalettized` regression guard |
| 2 — Factory | GenerationEngineFactory.swift + GenerationViewModel.swift | indirect via Step 9 smoke #1 + #5 | factory file header explains AppShell-not-ImagingCore decision | `engineName` log tags variant per generation | smoke #1, #5 |
| 3 — Manager multi-file | ModelDownloadManager.swift +180; ModelDownloader.swift +30 | NEW ModelDownloadManagerMultiFileTests +10 tests; Phase A.3's 9 preserved | doc comment cites `wisdom-NEW-candidate: multi-file-download-aggregate-progress-pattern` | os_log line per setPhase carrying item path | `test_legacyPalettizedDownload_stillUsesSingleFilePath` regression guard |
| 4 — Flux engine | FluxEngine/Flux2KleinEngine.swift +200 | Flux2KleinEngineSmokeTests +3 (1 always, 2 gated) | engine header cites locked decisions #1, #6, #7 + spike paths | engineName="flux2-klein"; metallib SHA logged at probe | `test_probe_metallibPresentInBundle` regression guard |
| 5 — Metallib | scripts/copy-mlx-metallib.sh; Resources/mlx.metallib; .gitattributes | Step 4's probe test asserts presence | script doc + `wisdom-NEW-candidate: mlx-metallib-bundling-codesign-discipline` | metallib SHA → `docs/proofs/imaging-a4-flux-klein/metallib-sha.txt` | `codesign --verify` in release script |
| 6 — Settings UI | SettingsView.swift +100 | manual smoke (Step 9 #2, #5) | code comment cites honest-positioning anchor (§1) | picker selection in UserDefaults | manual smoke |
| 7 — Generate UI | GenerationViewModel.swift +5; GenerateView.swift +25 | manual smoke (Step 9 #4) | code comment on banner copy cites operator lock | engineName + variant pill in UI | manual smoke |
| 8 — License | SettingsView.swift +30; docs/proofs/imaging-a4-flux-klein/LICENSES.md | manual visual | LICENSES.md is the substrate artifact | n/a | none beyond visual |
| 9 — Test+Smoke | (no new code) | full `swift test` GREEN target 210+ | proofs dir + spike `VERDICT-NADEZHDA-spike.md` archived | per-generation timing in logs | 7-item smoke checklist |
| 10 — Mirror (bonus) | scripts/flux-mirror-upload.sh; catalog comment block | `curl -I` parity | mirror URL fallback documented in catalog | upload SHA logs → `flux-fallback-pins.json` | weekly cron extension to Phase A.3's r2-pin-drift workflow |
| 11 — Ship | genesis.json, version bump, appcast | full test GREEN + 7 smoke pass | handoff file + Sparkle release notes | Sparkle appcast = ship signal | `wisdom-NEW-candidate: macos-major-bump-sparkle-appcast-minimumSystemVersion` |
| 12 — Customer | (n/a) | (n/a) | `VERDICT-NADEZHDA-shipped.md` placeholder | (n/a) | customer-empirical loop IS the living check |

---

## 6. Estimated Effort + Ship Criteria (~30 lines)

**Effort breakdown:**
- Step 0 (Package.swift + macOS bump): 0.5 day
- Step 1 (Catalog + EngineKind + fluxKlein): 0.5 day
- Step 3 (Manager multi-file refactor): 1 day
- Step 4 (Flux2KleinEngine): 1.5 days (includes 1h API alignment + 1 smoke render)
- Step 5 (Metallib bundling): 0.5 day
- Step 2 (Factory + VM wire): 0.5 day
- Step 6 (Settings UI): 0.5 day
- Step 7 (GenerateView): 0.25 day
- Step 8 (Licenses): 0.25 day
- Step 9 (Tests + smoke): 1 day
- Step 10 (Mirror bonus): 0.5 day if time
- Step 11 (Ship): 0.25 day
- **Buffer: 1 day** (bus-factor-1, metallib codesign, Sparkle compat, multi-file edge cases)

**Total: ~7-8 days raw.** Phase A.3 compressed ~10 days plan → ~3.5h ship via customer-empirical doctrine; FLUX has more genuine architectural work (multi-file download, new engine target, metallib discipline) so realistic compression is 5-7 days, not 1-2 days.

**Ship criteria (binary):**
1. 210+ `swift test` GREEN (with at most 2 XCTSkip on bundle-gated FLUX smoke tests).
2. All 7 manual smoke items pass on operator's M4 Pro macOS 15.7.5.
3. Operator visual verdict on FLUX output from inside the shipped app (not just the spike CLI): "matches spike pack quality."
4. `codesign --verify --deep --strict` GREEN on signed DMG.
5. Sparkle appcast push complete with `minimumSystemVersion=15.0` on v0.6.0.0 entry.
6. Nadezhda gets v0.6.0.0 update notification (next-launch Sparkle pickup).

**NOT ship criteria (deferred):**
- Nadezhda's real-workflow verdict (Step 12, ongoing).
- vps.tc + R2 mirror (Step 10 bonus, can ship in v0.6.0.1).
- Per-item resumeData (v0.6.x polish).
- FLUX img2img / eraser integration (Phase B).

---

## 7. Cycle Position + Cross-References (~20 lines)

**Previous cycle:** Phase A.3 SHIPPED v0.5.0.0 (LoRA variant). Nadezhda verdict on LoRA: insufficient. Operator pivoted to FLUX research (1 day) → spike (1 day) → spike verdict ("kalite daha iyi… bununla ilerleyelim") → this plan.

**This cycle:** Phase A.4 v0.6.0.0 (FLUX variant). Nadezhda spike verdict positive but bounded ("DALL-E seviyesinde değil"). Plan calibrated to ship honestly-framed FLUX integration; real Etsy workflow verdict pending.

**Next cycle (Phase A.5) trigger conditions:**
- **Positive Nadezhda real-workflow verdict** (FLUX = good enough for paid Etsy work): polish (8-step quality bump, dynamic prompting) and/or FLUX LoRA training (her style fine-tune on Klein 4B).
- **Mid verdict** (FLUX = better but still preview-class): pivot to upscale + eraser core focus per `/tmp/flux-research.md` §3 "Yol C"; generation becomes secondary feature.
- **Negative verdict** (FLUX = no improvement): honest deprecation of generation feature; Genesis Imaging value = editing pipeline.

**Cross-references:**
- Phase A.3 plan: `docs/plans/2026-05-17-genesis-imaging-phase-a3-lora-coloring-book.md`
- Phase A.3 handoff: `~/.claude/projects/-Users-okan-yucel-Desktop-genesisv3/memory/handoff_2026-05-17_genesis-imaging-phase-a3-lora-coloring-book-shipped-cycle-end.md`
- FLUX research deliverable: `/tmp/flux-research.md`
- Spike artifact: `/Users/okan.yucel/Desktop/genesis-imaging/tools/flux-spike/`
- Spike eval pack (shipped to Nadezhda): `~/Desktop/flux-nadezhda-test/`
- Vendor alignment: VIS-016 (Apple Silicon edition vendor lineup)
- Companion vision: VIS-018 (unified Genesis Imaging product narrative)
- Substrate gap: experience_db MCP subagent disconnect (3rd cycle flagged)

---

## 8. Architectural Trade-offs Sidebar (~30 lines)

**WWOD-compliant — enumerate alternatives considered for risky decisions:**

### EngineKind on Variant vs separate ModelCatalog
- **Picked:** Single `SDXLModelCatalog` with `engineKind` computed property per variant. Future variants (Phase B FLUX dev, Phase C cloud DALL-E) extend one enum.
- **Considered:** Separate `CoreMLCatalog` + `FluxCatalog` enums with a top-level `ModelVariant` union type. Cleaner naming, but doubles the catalog test surface and requires VM to switch on union cases everywhere. Operator picked unified for v0.6.0.0; rename `SDXLModelCatalog` → `ModelCatalog` deferred to v0.7.x cleanup.

### Bundle metallib vs require Homebrew mlx
- **Picked:** Bundle `mlx.metallib` in app Resources at build time. Zero customer setup; portable across machines without Homebrew.
- **Considered:** Require customer to `brew install mlx` and symlink to `/opt/homebrew/lib/mlx.metallib` (matches spike pattern). Rejected: hostile UX for non-developer customers like Nadezhda; one of two reasons the spike artifact isn't a customer-shippable build.

### HF direct vs branded mirror primary
- **Picked:** Hugging Face direct (`black-forest-labs/FLUX.2-klein-4B/...`). Anonymous pull works per spike; no infrastructure dep.
- **Considered:** apps.softwareasan.ai + R2 mirror primary (Phase A.3 LoRA pattern). Rejected primary because: (a) ~11 GB egress eats R2 free tier fast under viral traffic; (b) HF CDN is faster for most customers; (c) HF availability is high (~99.9% per their SLA). Mirror retained as Step 10 bonus insurance with manual catalog flip mechanism.

### macOS 14 conditional FLUX vs hard 15 bump
- **Picked:** Hard bump `platforms: [.macOS(.v15)]`. Sonoma users stay on v0.5.x via Sparkle's minimumSystemVersion gate.
- **Considered:** Conditional compilation — `#if canImport(MLX)` + runtime macOS version check, ship FLUX engine only on Sequoia+. Rejected because: (a) flux-2-swift-mlx's transitive deps may not even compile on .v14 SPM target — bumping the platform is the simplest test; (b) conditional engine surfaces a phantom "FLUX unavailable" state in Settings UI that needs separate copy; (c) Sonoma usage is shrinking (Sequoia released 2024, almost 2 years ago by 2026-05). Locked decision #1.

### Single shared `mlx.metallib` vs per-engine isolated metallibs
- **Picked:** Single metallib in FluxEngine target's Resources. Future MLX-based engines (e.g., Z-Image, HiDream) could also reference it.
- **Considered:** Each MLX engine target ships its own metallib. Rejected: 10-50 MB × N targets is wasteful; MLX metallib is engine-agnostic by design.

---

**END OF PLAN** — Plan total: ~870 lines. Ship signal for MAX: persist verbatim to `/Users/okan.yucel/Desktop/genesisv3/docs/plans/2026-05-18-genesis-imaging-phase-a4-flux-klein-engine.md`; begin Step 0 with `swift package resolve` + baseline `swift test` to confirm 194 GREEN before any code changes.

---

### Critical Files for Implementation

- /Users/okan.yucel/Desktop/genesis-imaging/Package.swift
- /Users/okan.yucel/Desktop/genesis-imaging/Sources/ImagingCore/Generation/SDXLModelCatalog.swift
- /Users/okan.yucel/Desktop/genesis-imaging/Sources/ImagingCore/Generation/ModelDownloadManager.swift
- /Users/okan.yucel/Desktop/genesis-imaging/Sources/FluxEngine/Flux2KleinEngine.swift (NEW)
- /Users/okan.yucel/Desktop/genesis-imaging/Sources/AppShell/GenerationEngineFactory.swift (NEW)