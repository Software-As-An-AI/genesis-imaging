# Genesis Imaging

**On-device image upscaling for macOS — Apple Silicon native.**

Drop a low-resolution image, get a high-resolution version back. Everything runs locally on your Mac: no upload, no cloud, no API key, no telemetry. Real-ESRGAN under the hood; Apple Neural Engine when available, Vulkan/Metal as fallback.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/Software-As-An-AI/genesis-imaging)](https://github.com/Software-As-An-AI/genesis-imaging/releases)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014%2B%20Apple%20Silicon-lightgrey)](https://github.com/Software-As-An-AI/genesis-imaging/releases)
[![Auto-update](https://img.shields.io/badge/Auto--update-Sparkle-orange)](https://sparkle-project.org)

> **Status:** Alpha, fast-moving. Feedback from early users shapes weekly releases.

---

## What

Genesis Imaging is a small, focused macOS app that upscales images 4× using Real-ESRGAN. The app is the first standalone consumer of `ImagingCore` — a Swift module that hides engine details behind a single `UpscaleEngine` protocol, so the same UI works against either of two backends:

- **Core ML on the Apple Neural Engine** — the default. 100% ANE layer residency, ~5× faster than the Vulkan path on M-series Macs (see [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md)).
- **Real-ESRGAN-ncnn-vulkan subprocess** — fallback path. Vulkan → MoltenVK → Metal GPU. Useful for cross-engine output comparison.

Everything is on-device. The app does not phone home.

## Features

- **Single-file upscale** — drag-drop or click to pick → preview → upscale → save with `-upscaled-x4` suffix.
- **Batch upscale** (shipped v0.3.0) — multi-file drop → queue with per-item ⚙ model/scale override → pre-flight validation (disk space, memory budget, supported formats, 8 issue types) → sequential processing with ETA → soft cancel → end summary.
- **Engine selection** — choose Core ML (default), ncnn-vulkan, or `.auto` (Core ML when available, fallback to ncnn) from Settings.
- **Sparkle auto-update** — signed ed25519 appcast at `apps.softwareasan.ai/genesis-imaging`. Menubar → Genesis Imaging → *Check for Updates…*
- **Bundled models** — `realesrgan-x4plus` (general photo), `realesrgan-x4plus-anime` (2D art / line work).
- **Signed + notarized** — Developer ID Application signed, hardened runtime, notarized through Apple.

## Performance

On Apple M4 Pro, Real-ESRGAN x4plus, 1 warm-up + 3 timed runs (mean):

| Input | Core ML (ANE) | ncnn-vulkan | Speedup |
|---|---|---|---|
| 256×256 | 0.61 s | 1.14 s | 1.87× |
| 512×512 | 0.61 s | 3.20 s | **5.22×** |
| 1024×1024 (4-tile) | 2.45 s | 11.79 s | **4.81×** |

Cross-engine SSIM ≥ 0.986 on every fixture — outputs are visually indistinguishable. Full table, fixtures, methodology, and quality numbers: [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

## System requirements

- macOS 14.0 (Sonoma) or newer
- Apple Silicon (M1 / M2 / M3 / M4 — including Pro / Max variants)
- ~150 MB disk (app + bundled models)
- 16 GB unified memory minimum; 32 GB recommended for inputs ≥ 4K

Intel Macs are not currently supported.

## Install

1. Open [**apps.softwareasan.ai/genesis-imaging**](https://apps.softwareasan.ai/genesis-imaging) in **Safari**. Safari is recommended — other browsers can attach a sandboxed-creator extended attribute that Gatekeeper rejects. If you must use another browser and the app refuses to launch, run `xattr -dr com.apple.quarantine /Applications/Genesis\ Imaging.app` once.
2. Click *Mac için indir* / download.
3. Open the DMG, drag **Genesis Imaging** to `/Applications`.
4. Launch from `/Applications`.

Future updates arrive in-app via Sparkle. You can also pull DMGs from [GitHub Releases](https://github.com/Software-As-An-AI/genesis-imaging/releases).

## Quick start

**Single file.** Drag an image onto the drop zone (or click to open a file picker). Hit *Upscale*. Save dialog opens with the suggested filename.

**Batch (2+ files).** Drag multiple files. The queue view appears. Each row has a ⚙ icon for per-item model/scale override. Optionally pick *Save all to…* to route every output into one folder; otherwise outputs land next to their sources with the `-upscaled-x4` suffix. Click *Başlat*. Soft-cancel any time — in-flight item finishes, queue stops.

## Build from source

Requires Swift 5.10+ toolchain and macOS 14+ SDK. No Xcode needed for command-line build.

```bash
git clone https://github.com/Software-As-An-AI/genesis-imaging.git
cd genesis-imaging

# Fetch the ncnn-vulkan binary + Real-ESRGAN models (gitignored, ~80 MB)
./scripts/fetch-ncnn-binary.sh

# Fetch the Core ML model (gitignored, ~70 MB)
./scripts/fetch-coreml-model.sh

# Build (release) + package as .app bundle
swift build -c release
./scripts/package-app.sh

open "build/Genesis Imaging.app"
```

Run the test suite (78 tests as of v0.3.0.4):

```bash
swift test
```

## Architecture

```
Sources/
├── ImagingCore/    Pure logic: UpscaleEngine protocol, BatchQueue,
│                   PreflightValidator, OutputWriter, TileSplitter,
│                   SettingsStore, HistoryStore, Notifier
├── NcnnEngine/     ncnn-vulkan subprocess wrapper + progress parser
├── CoreMLEngine/   Core ML driver, ANE delegation, ComputePlanInspector
└── AppShell/       SwiftUI views, ViewModels, EngineFactory, lifecycle
```

The `UpscaleEngine` protocol in `ImagingCore` is the only contract the UI depends on, so swapping engines (or adding a third) requires no AppShell changes. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/ENGINES.md`](docs/ENGINES.md), and [`docs/PROTOCOL.md`](docs/PROTOCOL.md) for the full picture.

## Roadmap

This is an alpha. Things land fast, things move around.

**Current focus.** Stability, UX polish, INT8 / quantized Core ML weights to shrink the bundled model.

**Backlog (deferred).** Custom AppIcon, additional Real-ESRGAN model variants, multi-window batch, optional cloud-burst path for users without Apple Silicon (only if there is genuine demand — on-device remains the default and the moat).

## Acknowledgments

Genesis Imaging stands on the shoulders of these projects. Please respect their licenses if you redistribute.

- **[Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN)** — model architecture and weights, by xinntao et al., BSD 3-Clause.
- **[Real-ESRGAN-ncnn-vulkan](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan)** — Vulkan inference binary, BSD 3-Clause. Bundled at build time, not redistributed in source.
- **[ncnn](https://github.com/Tencent/ncnn)** — neural network inference framework by Tencent, BSD 3-Clause. Statically linked into the Vulkan binary.
- **[MoltenVK](https://github.com/KhronosGroup/MoltenVK)** — Vulkan→Metal translation by Khronos / Brenwill Workshop, Apache 2.0.
- **[Sparkle](https://sparkle-project.org)** — auto-update framework for macOS by the Sparkle Project, MIT.
- **Apple** — Core ML, Vision, Metal, AppKit, Accelerate.
- **[mszpro/CoreML_RealESRGAN](https://github.com/mszpro/CoreML_RealESRGAN)** — Core ML conversion of Real-ESRGAN x4plus used as the Faz 2 model.

See [LICENSE](LICENSE) for the bundled-component license summary.

## License

[MIT](LICENSE) — copyright (c) 2026 Okan Yucel / Genesis Imaging. App code is MIT. Bundled binaries and model weights retain their upstream licenses (see *Acknowledgments* and [LICENSE](LICENSE)).

## Links

- **Download:** https://apps.softwareasan.ai/genesis-imaging
- **Releases:** https://github.com/Software-As-An-AI/genesis-imaging/releases
- **Issues:** https://github.com/Software-As-An-AI/genesis-imaging/issues
- **Benchmarks:** [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md)
- **Architecture:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Engine protocol:** [`docs/PROTOCOL.md`](docs/PROTOCOL.md)

<!-- TODO: real screenshots before v0.3.1 — single-file upscale + batch queue + preflight issues view -->
