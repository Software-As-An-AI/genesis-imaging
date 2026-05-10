# Genesis Imaging

On-device image upscaling for macOS — Apple Silicon native.

> **Status:** Faz 1 (in development) — Real-ESRGAN ncnn-vulkan subprocess.
> **Faz 2 (planned):** Core ML migration with Apple Neural Engine acceleration.

## What

Drop a low-resolution image into the app — get a high-resolution version back. Runs entirely on your Mac (no upload, no cloud, no API key needed).

- **Engine (Faz 1):** Real-ESRGAN via `realesrgan-ncnn-vulkan` (Vulkan / MoltenVK)
- **Engine (Faz 2):** Core ML on Apple Neural Engine + GPU
- **Models:** general photo (4×), anime (4×), 2× lightweight, video frame
- **Privacy:** Image never leaves your machine. No telemetry, no analytics.

## Why

This is the first standalone consumer of `ImagingCore` — a small, engine-agnostic Swift module for on-device image processing. The project is part of Genesis's broader on-device imaging substrate exploration; future tools may share the same core.

See `docs/ARCHITECTURE.md` for module boundaries and `docs/PROTOCOL.md` for the `UpscaleEngine` contract.

## Requirements

- macOS 13.0 (Ventura) or newer
- Apple Silicon (M1 or newer) — Intel Macs not currently supported
- ~150 MB disk space (app + bundled models)

## Install

Download the latest signed/notarized DMG from [Releases](https://github.com/Software-As-An-AI/genesis-imaging/releases), open it, drag **Genesis Imaging** to `/Applications`.

## Develop

```bash
# Clone
git clone git@github.com:Software-As-An-AI/genesis-imaging.git
cd genesis-imaging

# Fetch ncnn binary + models
./scripts/fetch-ncnn-binary.sh

# Build & run
swift build
swift run

# Test
swift test

# Build .app bundle locally
./scripts/package-app.sh
open ./build/Genesis\ Imaging.app
```

## Release

```bash
./release.sh           # auto-bump patch → tag → push → GitHub Actions builds DMG
./release.sh minor     # bump minor
./release.sh v1.4.0    # explicit version
```

## License

MIT — see [LICENSE](LICENSE). Bundled third-party components retain their own licenses.
