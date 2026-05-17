# SDXL LoRA → Core ML Conversion Pipeline

Phase A.3 dev-time toolchain: fuse a SDXL LoRA into the base UNet/TextEncoder
weights, convert the merged pipeline to Core ML, palettize to ~3 GB, package
and upload to Cloudflare R2 for runtime download by Genesis Imaging.

This README documents the **dev-time** pipeline. The runtime (Genesis Imaging
app) consumes the resulting `.mlmodelc` bundle via `ModelDownloadManager`
from R2 — no Python at runtime.

## Why a sister venv (`.venv-lora` not `.venv`)

The existing `tools/coreml-conversion/.venv` was created for Real-ESRGAN
Core ML benchmarks (Faz 2 prep, May 11) and pins `numpy 2.4.4`. Apple's
`python_coreml_stable_diffusion` `setup.py` declares `numpy<1.24`, which
would force a destructive downgrade if merged. Sister venv `.venv-lora`
keeps both concerns isolated. ~3 GB extra disk, clean reuse for future LoRA
cycles (adventure book, anime, etc.).

## Lockdown decisions (operator-approved 2026-05-17)

| Decision | Value |
|---|---|
| LoRA candidate | `artificialguybr/ColoringBookRedmond-V2` (HF Hub, OpenRAIL-M, 1.4M downloads) |
| Fuse scale | 1.0 (full merge) |
| Palettization | `recipe_4_50_bit_mixedpalette` → ~3 GB final |
| Attention impl | `ORIGINAL` (macOS cpuAndGPU — `.cpuAndNeuralEngine` blocked by SDXL UNet ANE compile cost) |
| VAE encoder | converted YES (img2img insurance) |
| Storage | Cloudflare R2 `software-as-an-ai-models` bucket, HF mirror SKIPPED |
| Conversion machine | operator's M4 Pro (48 GB RAM, 46 GB free post-cleanup) |

Full plan: `~/Desktop/genesisv3/docs/plans/2026-05-17-genesis-imaging-phase-a3-lora-coloring-book.md`
Research extract: `~/Desktop/genesisv3/docs/extracts/2026-05-17-genesis-imaging-phase-a3-lora-research.md`

## Pipeline (5 steps)

| Step | Script | Wall time | Output |
|---|---|---|---|
| **0** | `setup-lora-env.sh` | 5-10 min | `.venv-lora/` with deps + python_coreml_stable_diffusion |
| **1** | `fuse-coloring-book-lora.py` | 10-30 min | `sdxl-coloring-book-fused/` diffusers checkpoint |
| **2** | `convert-fused-to-coreml.sh` | 2-3 h | `build/coreml-coloring-book/Resources/*.mlmodelc` |
| **3** | `palettize-bundle.py` | 30 min | `build/coreml-coloring-book-palettized/...` |
| **4** | `package-and-upload.sh` | 10 min | R2 URL + SHA256 pin |

Disk peak: ~30 GB intermediate (cleanup-as-you-go: SDXL base FP16 cache
deleted after fuse, fused checkpoint deleted after Core ML convert).

## Step 0 — Environment setup

```bash
cd /Users/okan.yucel/Desktop/genesis-imaging
swift build  # Ensure SwiftPM checkouts exist (.build/checkouts/ml-stable-diffusion)
cd tools/coreml-conversion
./setup-lora-env.sh
```

Verification (run after script):
```bash
source .venv-lora/bin/activate
python -c "from diffusers import StableDiffusionXLPipeline; print('ok')"
python -c "from python_coreml_stable_diffusion import torch2coreml; print('ok')"
```

## Step 1+ — TBD (next scripts ship as cycle proceeds)

## Known issues + workarounds

### Step 3 — Apple's `mixed_bit_compression_pre_analysis` module-import flickr fetch

Apple's `python_coreml_stable_diffusion.mixed_bit_compression_pre_analysis`
fetches 8 reference images from `farm{1-8}.staticflickr.com` **at module
import time** (top-level code, not inside a function). If any URL 404s, the
entire palettization path fails to import.

Discovered: 2026-05-17 Step 0 venv setup. One of the flickr URLs returns
non-image bytes, breaks `Image.open()`.

**Step 3 mitigations (TBD — pick at Step 3 time):**
1. Pre-download Apple's 8 reference images to a local cache + monkey-patch
   the URLs to `file://` before first import (fragile, needs venv hook).
2. Use coremltools' native palettization API (`ct.optimize.coreml.OpPalettizerConfig`)
   directly — bypass Apple's wrapper entirely. Recipe `recipe_4_50_bit_mixedpalette`
   is just a JSON spec mapping layer name → nbits; we can replicate it without
   Apple's pre-analysis re-running.
3. File issue upstream + use unpalettized FP16 bundle for v0.5.0.0 ship (~6 GB
   instead of ~3 GB), palettize in v0.5.0.1 once workaround lands.

### numpy `<1.24` constraint warning

Apple's `setup.py` declares `numpy<1.24` but coremltools 8.1 + torch 2.12
work fine with numpy 1.26. pip warns about dependency conflict — runtime is
unaffected. Safe to ignore.

### torch 2.12 not "tested" by coremltools 8.1

coremltools warns "max tested torch version 2.4.0". Apple ships ml-stable-diffusion
1.1.1 against an older torch; our 2.12 is newer. May surface edge cases at
conversion (Step 2). Fallback: pin `torch==2.4.0` if Step 2 fails.

### scikit-learn 1.8 not supported by coremltools

We pin `scikit-learn<1.6` to match coremltools 8.1's tested range. SDXL
conversion doesn't use sklearn anyway; this prevents noise warnings.

## Reproducibility

Re-running setup-lora-env.sh is idempotent (skips venv creation, upgrades
pip packages). Apple's `python_coreml_stable_diffusion` is installed
non-editable from the SwiftPM checkout — if SwiftPM re-clones the checkout
(e.g., Package.resolved bumps the ml-stable-diffusion tag), rerun the setup
script to refresh the site-packages copy.

## Cleanup (after successful R2 upload)

```bash
# Keep .venv-lora (~3 GB) for future LoRA cycles.
# Reclaim ~30 GB intermediate:
rm -rf sdxl-base-fp16/ sdxl-coloring-book-fused/ build/ lora-weights/
```
