#!/usr/bin/env bash
# tools/coreml-conversion/setup-lora-env.sh
#
# Phase A.3 LoRA conversion Python environment setup.
#
# Creates a sister venv at tools/coreml-conversion/.venv-lora (separate from
# the Real-ESRGAN bench .venv to avoid numpy version conflicts) and installs
# Apple's python_coreml_stable_diffusion in non-editable mode from the local
# SwiftPM checkout (.build/checkouts/ml-stable-diffusion), so we don't need a
# second clone of the upstream repo.
#
# Idempotent: rerun is safe (skips venv creation if .venv-lora exists, pip
# upgrade handles existing packages).
#
# Verification: runs `python -c 'import python_coreml_stable_diffusion'` and a
# minimal diffusers import probe at the end.
#
# Reference: docs/plans/2026-05-17-genesis-imaging-phase-a3-lora-coloring-book.md §Step 0

set -euo pipefail

# ── Paths ───────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
VENV_DIR="$HERE/.venv-lora"
APPLE_CHECKOUT="$REPO/.build/checkouts/ml-stable-diffusion"

# ── Preflight ───────────────────────────────────────────────────────────────
echo "── Preflight ──"
echo "  repo:           $REPO"
echo "  venv target:    $VENV_DIR"
echo "  apple checkout: $APPLE_CHECKOUT"

if [ ! -d "$APPLE_CHECKOUT" ]; then
    echo "ERROR: Apple ml-stable-diffusion checkout not found at $APPLE_CHECKOUT" >&2
    echo "Run \`swift build\` in $REPO first to populate SwiftPM checkouts." >&2
    exit 1
fi

if [ ! -f "$APPLE_CHECKOUT/setup.py" ]; then
    echo "ERROR: $APPLE_CHECKOUT/setup.py missing — checkout may be partial." >&2
    exit 1
fi

PY="$(command -v python3.12 || command -v python3 || true)"
if [ -z "$PY" ]; then
    echo "ERROR: python3.12 (or python3) not on PATH." >&2
    exit 1
fi
echo "  python:         $PY ($("$PY" --version))"

# ── Disk check (need ~5 GB for venv + torch + diffusers) ────────────────────
AVAIL_GB=$(df -g / | tail -1 | awk '{print $4}')
if [ "$AVAIL_GB" -lt 10 ]; then
    echo "ERROR: only ${AVAIL_GB} GB free on /. Need ≥10 GB for venv + torch wheels." >&2
    exit 1
fi
echo "  disk free:      ${AVAIL_GB} GB ✓"

# ── Create venv (idempotent) ────────────────────────────────────────────────
if [ -d "$VENV_DIR" ]; then
    echo ""
    echo "── Reusing existing venv at $VENV_DIR ──"
else
    echo ""
    echo "── Creating venv at $VENV_DIR ──"
    "$PY" -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
echo "  active python:  $(which python) ($(python --version))"

# ── Upgrade pip + install deps ──────────────────────────────────────────────
echo ""
echo "── Upgrading pip ──"
python -m pip install --quiet --upgrade pip wheel setuptools

# Pin strategy:
#   - diffusers >=0.27 for SDXL load_lora_weights + fuse_lora support
#   - transformers >=4.36 for SDXL CLIP-VIT-L tokenizer compat
#   - coremltools 8.1 matches existing .venv (consistent across both bench
#     and lora venvs; Apple ml-stable-diffusion accepts >=7.0)
#   - numpy <2 because coremltools 8.1 + scipy 1.x play poorly with numpy 2.x
#   - peft installed by diffusers transitive; explicit pin for clarity
#   - safetensors required by diffusers for LoRA file loading
#   - huggingface_hub for ColoringBookRedmond-V2 download

echo ""
echo "── Installing pinned deps (~3-5 GB download, may take 5-10 min) ──"
python -m pip install \
    "diffusers[torch]>=0.27,<0.30" \
    "transformers>=4.36,<4.45" \
    "accelerate>=0.30,<1.0" \
    "huggingface_hub>=0.23,<1.0" \
    "peft>=0.10,<0.15" \
    "safetensors>=0.4" \
    "coremltools==8.1" \
    "numpy<2" \
    "scipy>=1.10" \
    "scikit-learn<1.6" \
    "invisible-watermark" \
    "matplotlib" \
    "pytest"  # required by coremltools.converters.mil.testing_utils, imported transitively by python_coreml_stable_diffusion.chunk_mlprogram

# ── Install Apple's python_coreml_stable_diffusion from local checkout ──────
# Non-editable (-e omitted): copies to site-packages, decouples from SwiftPM
# rebuild cycle. Re-run setup script if Apple updates Package.resolved.
echo ""
echo "── Installing python_coreml_stable_diffusion from $APPLE_CHECKOUT ──"
python -m pip install --no-deps "$APPLE_CHECKOUT"

# ── Verification probes ─────────────────────────────────────────────────────
echo ""
echo "── Verifying imports ──"
python - <<'PY'
import sys
print(f"python: {sys.version.split()[0]}")

import torch
mps_ok = torch.backends.mps.is_available()
print(f"torch:  {torch.__version__} (MPS: {mps_ok})")

import coremltools as ct
print(f"coremltools: {ct.__version__}")

import diffusers
print(f"diffusers: {diffusers.__version__}")

import transformers
print(f"transformers: {transformers.__version__}")

import peft
print(f"peft: {peft.__version__}")

import python_coreml_stable_diffusion as pcsd
print(f"python_coreml_stable_diffusion: ok (module loaded)")

import huggingface_hub
print(f"huggingface_hub: {huggingface_hub.__version__}")

# Quick StableDiffusionXLPipeline class import probe (does NOT load weights).
from diffusers import StableDiffusionXLPipeline
print(f"StableDiffusionXLPipeline: importable")

# torch2coreml CLI probe
from python_coreml_stable_diffusion import torch2coreml
print(f"torch2coreml: importable ({torch2coreml.__file__})")

# Step 3 palettization probe — Apple's mixed_bit_compression_pre_analysis
# fetches 8 reference images from flickr at module import time. If any URL
# is dead, import fails. NOT a Step 0 blocker — Step 3 has fallback paths
# (coremltools native palettization OR pre-cached reference images).
try:
    from python_coreml_stable_diffusion import mixed_bit_compression_apply  # noqa
    print(f"mixed_bit_compression_apply: importable (Step 3 ready)")
except Exception as e:
    print(f"⚠ mixed_bit_compression_apply import deferred to Step 3 workaround: {type(e).__name__}")
    print(f"  (Apple module fetches flickr URLs at import time; resolve in Step 3 plan)")

print("")
print("✓ Step 0 complete — env ready for Step 1 (fuse + convert).")
print("  Step 3 palettization may need workaround (see SDXL_LORA_README.md).")
PY

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo "Phase A.3 LoRA conversion env READY."
echo ""
echo "Next:"
echo "  source $VENV_DIR/bin/activate"
echo "  cd $HERE"
echo "  ./fuse-coloring-book-lora.py    # Step 1 (next script)"
echo "──────────────────────────────────────────────────────────────────────"
