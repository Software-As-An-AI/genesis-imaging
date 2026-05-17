#!/usr/bin/env bash
# tools/coreml-conversion/convert-fused-to-coreml.sh
#
# Phase A.3 Step 2 — convert the LoRA-fused SDXL diffusers checkpoint into a
# Core ML bundle using Apple's torch2coreml CLI.
#
# Inputs:
#   ./sdxl-coloring-book-fused/   (~6.5 GB, output of Step 1)
#
# Output:
#   ./build/coreml-coloring-book/Resources/
#     ├── Unet.mlmodelc/
#     ├── TextEncoder.mlmodelc/
#     ├── TextEncoder2.mlmodelc/
#     ├── VAEDecoder.mlmodelc/
#     ├── VAEEncoder.mlmodelc/
#     ├── vocab.json
#     └── merges.txt
#
# Wall time: ~2-3 hours on M4 Pro (UNet dominates; VAE encoder + text encoders
# are quick).
#
# Flags rationale:
#   --xl-version                : SDXL-specific UNet config (vs SD1.5)
#   --attention-implementation ORIGINAL : macOS cpuAndGPU path
#                                 (SPLIT_EINSUM is for iOS ANE — SDXL UNet
#                                 ANE compile is prohibitively slow on
#                                 macOS, lesson from Phase A.2 v0.4.1.2)
#   --bundle-resources-for-swift-cli : creates the Swift-loadable nested
#                                 directory layout matching what
#                                 StableDiffusionXLPipeline(resourcesAt:)
#                                 expects
#   --convert-vae-encoder       : img2img insurance (eraser → img2img later)
#
# Run (unattended, ~3 h):
#     source .venv-lora/bin/activate
#     cd tools/coreml-conversion
#     ./convert-fused-to-coreml.sh
#
# Reference: docs/plans/2026-05-17-genesis-imaging-phase-a3-lora-coloring-book.md §Step 2
#            Apple ml-stable-diffusion README §Converting Stable Diffusion XL

set -euo pipefail

# ── Paths ───────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUSED_DIR="$HERE/sdxl-coloring-book-fused"
OUT_DIR="$HERE/build/coreml-coloring-book"
VENV_DIR="$HERE/.venv-lora"

# ── Preflight ───────────────────────────────────────────────────────────────
echo "── Preflight ──"
echo "  fused checkpoint: $FUSED_DIR"
echo "  output:           $OUT_DIR"

if [ ! -d "$FUSED_DIR" ]; then
    echo "ERROR: fused checkpoint missing — run ./fuse-coloring-book-lora.py first" >&2
    exit 1
fi

if [ ! -d "$VENV_DIR" ]; then
    echo "ERROR: .venv-lora missing — run ./setup-lora-env.sh first" >&2
    exit 1
fi

if [ "${VIRTUAL_ENV:-}" != "$VENV_DIR" ]; then
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
fi

# Disk: Step 2 peak ~10-15 GB intermediate. Need fused (6.5 GB) + output
# (~7-10 GB FP16 mlmodelc) + scratch. Conservative floor 25 GB free.
AVAIL_GB=$(df -g / | tail -1 | awk '{print $4}')
if [ "$AVAIL_GB" -lt 25 ]; then
    echo "ERROR: only ${AVAIL_GB} GB free on /. Need ≥25 GB for Step 2." >&2
    echo "Hint: free space by removing earlier Step 1 cache or unused apps." >&2
    exit 1
fi
echo "  disk free:        ${AVAIL_GB} GB ✓"

# ── Output prep ─────────────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"

# ── Run conversion ──────────────────────────────────────────────────────────
echo ""
echo "── torch2coreml conversion (~2-3 h wall time, unattended) ──"
echo "  Start: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Each --convert-* flag triggers a separate stage. Sequential, not parallel
# (each stage hogs memory). UNet is the long one.
START_EPOCH=$(date +%s)

python -m python_coreml_stable_diffusion.torch2coreml \
    --model-version "$FUSED_DIR" \
    --convert-text-encoder \
    --convert-vae-decoder \
    --convert-vae-encoder \
    --convert-unet \
    --xl-version \
    --attention-implementation ORIGINAL \
    --bundle-resources-for-swift-cli \
    -o "$OUT_DIR"

END_EPOCH=$(date +%s)
ELAPSED=$(( END_EPOCH - START_EPOCH ))
echo ""
echo "  End:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Wall:  $(( ELAPSED / 60 )) min $(( ELAPSED % 60 )) sec"

# ── Verify output structure ─────────────────────────────────────────────────
echo ""
echo "── Verifying output bundle structure ──"
RESOURCES="$OUT_DIR/Resources"
if [ ! -d "$RESOURCES" ]; then
    echo "ERROR: expected $RESOURCES/ — torch2coreml output layout unexpected" >&2
    ls -la "$OUT_DIR" >&2
    exit 2
fi

EXPECTED=(
    "Unet.mlmodelc"
    "TextEncoder.mlmodelc"
    "TextEncoder2.mlmodelc"
    "VAEDecoder.mlmodelc"
    "VAEEncoder.mlmodelc"
    "vocab.json"
    "merges.txt"
)

MISSING=()
for entry in "${EXPECTED[@]}"; do
    if [ ! -e "$RESOURCES/$entry" ]; then
        MISSING+=("$entry")
    fi
done

if [ ${#MISSING[@]} -ne 0 ]; then
    echo "ERROR: missing expected output entries: ${MISSING[*]}" >&2
    echo "Got:" >&2
    ls "$RESOURCES" >&2
    exit 3
fi

SIZE_GB=$(du -sh "$RESOURCES" 2>/dev/null | awk '{print $1}')
echo "  ✓ all expected entries present"
echo "  ✓ Resources size: $SIZE_GB"

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo "Step 2 complete."
echo ""
echo "Optional cleanup (reclaim ~6.5 GB by removing the fused checkpoint —"
echo "Step 3 only needs the Core ML bundle, not the diffusers source):"
echo "  rm -rf $FUSED_DIR"
echo ""
echo "Next: Step 3 palettization (Apple flickr-import workaround needed —"
echo "      see SDXL_LORA_README.md §Known issues)"
echo "──────────────────────────────────────────────────────────────────────"
