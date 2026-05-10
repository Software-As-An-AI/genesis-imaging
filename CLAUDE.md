# CLAUDE.md — Genesis Imaging

## Identity

When this file loads, respond: **"genesis-imaging-worker online, Orkestratör."**

Sub-project agent ID: `genesis-imaging-worker`. Inherit Genesis methodology stack via parent `/Users/okan.yucel/Desktop/genesisv3/CLAUDE.md` symlinks (`.claude/skills`, `.claude/commands`).

## Project

On-device image upscaling for macOS, Apple Silicon native. First consumer of `ImagingCore` substrate (Genesis Imaging umbrella; future tools may share core). See:
- Plan: `/Users/okan.yucel/Desktop/genesisv3/docs/plans/enumerated-herding-scroll.md`
- Architecture: `docs/ARCHITECTURE.md`
- Engine protocol: `docs/PROTOCOL.md`
- Engines (Faz 1 + Faz 2): `docs/ENGINES.md`

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI (macOS 13+)
- **Build:** SwiftPM only — **NO Xcode project**
- **Engine Faz 1:** `realesrgan-ncnn-vulkan` v0.2.0 (subprocess, Vulkan/MoltenVK)
- **Engine Faz 2:** Core ML (Apple Neural Engine + GPU)
- **Distribution:** GitHub Releases, signed/notarized DMG (Developer ID Application)
- **CI:** GitHub Actions (`macos-14` runner)

## Architecture (modular by design)

```
Sources/
├── ImagingCore/      # Engine-agnostic — UpscaleEngineProtocol, ImageIO, TileSplitter, History
├── NcnnEngine/       # Faz 1 — Process subprocess wrapper for ncnn binary
├── CoreMLEngine/     # Faz 2 — Core ML predict + Vision framework (Faz 1: notImplemented stub)
└── AppShell/         # SwiftUI app, ViewModels, EngineFactory
```

**Boundary discipline (P0.90 substrate):** `ImagingCore` MUST NOT import any Engine. Engines import `ImagingCore` (one-way). This guarantees future framework spin-off is zero-code-change.

## Critical Rules

- ❌ **Don't** add Xcode project — pure SwiftPM only
- ❌ **Don't** import `NcnnEngine` or `CoreMLEngine` from `ImagingCore`
- ❌ **Don't** modify Genesis core ports (5000/5173) — this is a native app, no servers
- ❌ **Don't** write image bytes outside `~/Library/Application Support/GenesisImaging/` and `~/Library/Logs/GenesisImaging/`
- ✅ **Do** keep `UpscaleEngine` protocol the single source of truth — both engines conform identically
- ✅ **Do** write tests before implementation (P0.40 TDD)
- ✅ **Do** consult `get_relevant_wisdom(task_context=..., agent="genesis-imaging-worker")` before any new file (P0.51)
- ✅ **Do** treat `release.sh` tag operations as P0.50 destructive — operator confirmation

## Active Protocols

- **P0.30** Subproject Protocol — `.genesis_initialized` marker enforced
- **P0.40** Test-Driven Development — RED-GREEN-REFACTOR for every Engine impl
- **P0.50** Destructive Action Guard — `release.sh` tag/push, file deletes
- **P0.51** Per-Task Wisdom Gate — fresh wisdom query per new task context
- **P0.83** Session Boundary — never restart Genesis core (5000/5173) from this sub-project
- **P0.90** Permanence Stack — every non-trivial change covers all 5 layers (code/test/substrate/observability/living-check)

## Commands

```bash
# Develop
swift build                              # Compile all targets
swift test                               # Run unit + integration tests
swift run                                # Launch GenesisImaging executable (dev mode)

# Build app bundle
./scripts/build.sh                       # swift build -c release
./scripts/package-app.sh                 # Assemble .app + Info.plist + Resources
./scripts/verify-app.sh                  # codesign --verify smoke

# Fetch ncnn binary (one-time, after clone)
./scripts/fetch-ncnn-binary.sh

# Release (operator-triggered)
./release.sh                             # Auto-bump patch → tag → push → GitHub Actions
./release.sh minor                       # Bump minor
./release.sh v1.0.0                      # Explicit version
```

## Session Start (mandatory)

```
/genesisv3-workflow                      # ZORUNLU — wisdom gate + TDD enforcement
/project:session-start                   # guard + context recovery + whispers
```

```python
context = where_was_i("genesis-imaging")
wisdom = get_relevant_wisdom(task_context="[task]", agent="genesis-imaging-worker", limit=5)
whispers = get_pending_whispers(agent="genesis-imaging-worker", acknowledge=True)
session = start_session(topic="[task title]")
```

## Observability

- **Log:** `~/Library/Logs/GenesisImaging/upscale.log` (per job: timestamp + engine + duration + I/O paths)
- **History:** `~/Library/Application Support/GenesisImaging/history.json` (max 50 entries)
- **Engine health:** UI footer displays `EngineHealth` (engine name + version + detected device)

## Phases

- **Faz 1** (current): SwiftUI shell + ncnn-vulkan binary subprocess. Target: signed/notarized DMG, M4 acceptance.
- **Faz 2** (planned): Core ML engine, ANE delegation, A/B benchmark vs ncnn.

Phase plans: `/Users/okan.yucel/Desktop/genesisv3/docs/plans/enumerated-herding-scroll.md`

## References

- Genesis methodology: `/Users/okan.yucel/Desktop/genesisv3/CLAUDE.md`
- Sendikaos macOS substrate (reuse template): `/Users/okan.yucel/Desktop/genesisv3/projects/sendikaos-v2/.github/workflows/release.yml`
- Sendikaos launcher pattern: `/Users/okan.yucel/Desktop/genesisv3/projects/sendikaos-v2/go-api/macos-launcher/SendikaOSLauncher.swift`
