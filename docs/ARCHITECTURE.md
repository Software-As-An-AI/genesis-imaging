# Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                          AppShell                            │
│  (SwiftUI views, ViewModels, EngineFactory, app lifecycle)  │
│                                                              │
│  Imports: ImagingCore, NcnnEngine, CoreMLEngine             │
└──────┬───────────────────┬───────────────────┬──────────────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌────────────┐      ┌─────────────┐    ┌──────────────┐
│ NcnnEngine │      │ CoreMLEngine│    │              │
│  (Faz 1)   │      │  (Faz 2)    │    │              │
│            │      │             │    │              │
│ Imports:   │      │ Imports:    │    │              │
│ ImagingCore│      │ ImagingCore │    │              │
└──────┬─────┘      └──────┬──────┘    │              │
       │                   │           │              │
       ▼                   ▼           ▼              │
       └─────────────┬─────┘  ┌──────────────────────┘
                     │        │
                     ▼        ▼
              ┌──────────────────────┐
              │     ImagingCore      │
              │ (engine-agnostic)    │
              │                      │
              │ - UpscaleEngine      │  ← protocol (SSOT)
              │ - ImageIO            │
              │ - TileSplitter       │
              │ - FormatDetection    │
              │ - HistoryStore       │
              │ - SettingsStore      │
              │                      │
              │ Imports: nothing     │  ← critical invariant
              └──────────────────────┘
```

## Boundary Invariant

**`ImagingCore` MUST NOT import any Engine target.**

Why this matters:
- Future framework spin-off: Day we decide to ship `ImagingCore` as a standalone Swift Package (e.g., for Sendikaos Tevkifat companion or other Genesis editions), it's `git mv Sources/ImagingCore … && new Package.swift` — no code changes.
- Test isolation: `ImagingCoreTests` runs in seconds without any binary dependency or Core ML model.
- Pure contract layer: Adding a 3rd engine (MLX? custom Metal?) means adding one new target alongside `NcnnEngine`/`CoreMLEngine` — `ImagingCore` doesn't move.

Enforced by: target dependency graph in `Package.swift`. If someone adds `import NcnnEngine` to an `ImagingCore` file, `swift build` fails (no such dependency declared).

## Faz 2 Swap Strategy

Faz 2 begins by changing only:
1. `Sources/CoreMLEngine/CoreMLEngine.swift` — replace stub `init` and `upscale` body
2. Bundle a `.mlpackage` model into `Resources/`
3. `EngineFactory` learns to pick CoreML when settings ask for it

That's it. `AppShell` views, ViewModels, history schema, settings UI — all untouched.

## Why SwiftPM (not Xcode)

- Operator's Xcode learning curve = 0
- Pure CLI workflow: `swift build`, `swift test`, `swift run`
- Modular target graph enforces `ImagingCore` boundary at build time
- CI runs `swift build` on `macos-14` runner — same toolchain
- Cost: SwiftUI Preview canvas unavailable. Acceptable for Faz 1 scope (manual `swift run` verification).

## Future Extraction (NOT promised in V3)

If `ImagingCore` ever needs to ship as a Swift Package consumed by other apps:

```
git mv Sources/ImagingCore <new-repo>/Sources/ImagingCore
git mv Tests/ImagingCoreTests <new-repo>/Tests/ImagingCoreTests
# In new repo: write Package.swift exposing ImagingCore as library product
# In genesis-imaging: replace .target(name: "ImagingCore") with .package(url: ...)
```

No source file changes. The boundary discipline today purchases this option; we choose to exercise it only when a second consumer materializes.
