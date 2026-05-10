#!/usr/bin/env bash
# scripts/fetch-coreml-model.sh
#
# Downloads the pre-converted Real-ESRGAN Core ML model from HuggingFace
# (mszpro/CoreML_RealESRGAN), verifies SHA256, and places it under Resources/models/.
#
# Idempotent: skips download if SHA256 of existing .mlmodel matches.
# Run once per fresh clone; release CI also invokes this before signing.

set -euo pipefail

# ── Pinned source ───────────────────────────────────────────────────────────
SOURCE_URL="https://huggingface.co/mszpro/CoreML_RealESRGAN/resolve/main/RealESRGAN.mlmodel.zip"
EXPECTED_ZIP_SHA256="7aaa571fba87ba1a64317054ac33eec2cd39320c6fe797aeba3a6c9e1fe0726a"
# HF LFS metadata: 62125259 bytes (~59 MB zip); unzipped .mlmodel is ~64 MB
SOURCE_VERSION="2024-07-15-mszpro"

# ── Paths ───────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_MODELS_DIR="$ROOT/Resources/models"
DEST_MODEL="$DEST_MODELS_DIR/RealESRGAN_x4plus.mlmodel"
DEST_COMPILED="$DEST_MODELS_DIR/RealESRGAN_x4plus.mlmodelc"
CACHE_DIR="$ROOT/.build/cache/coreml"
CACHE_ZIP="$CACHE_DIR/RealESRGAN.mlmodel.zip"
VERSION_MARKER="$DEST_MODELS_DIR/.coreml-version"

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[fetch-coreml]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }

# ── Already installed? ──────────────────────────────────────────────────────
if [ -d "$DEST_COMPILED" ] && [ -f "$VERSION_MARKER" ]; then
    if [ "$(cat "$VERSION_MARKER")" = "$SOURCE_VERSION" ]; then
        success "Core ML compiled model already installed (version $SOURCE_VERSION)"
        info "  Compiled: $DEST_COMPILED"
        echo ""
        info "Force re-install: rm -rf $DEST_COMPILED $DEST_MODEL $VERSION_MARKER && $0"
        exit 0
    else
        warn "Found older version, will overwrite"
    fi
fi

# ── Download ────────────────────────────────────────────────────────────────
mkdir -p "$CACHE_DIR" "$DEST_MODELS_DIR"

if [ -f "$CACHE_ZIP" ]; then
    CACHED_SHA="$(shasum -a 256 "$CACHE_ZIP" | awk '{print $1}')"
    if [ "$CACHED_SHA" = "$EXPECTED_ZIP_SHA256" ]; then
        info "Using cached zip ($CACHE_ZIP)"
    else
        warn "Cached zip SHA mismatch — re-downloading"
        rm -f "$CACHE_ZIP"
    fi
fi

if [ ! -f "$CACHE_ZIP" ]; then
    info "Downloading from HuggingFace..."
    info "  URL: $SOURCE_URL"
    curl -sL --fail -o "$CACHE_ZIP" "$SOURCE_URL" || {
        error "Download failed"
        exit 1
    }
    DOWNLOADED_SHA="$(shasum -a 256 "$CACHE_ZIP" | awk '{print $1}')"
    if [ "$DOWNLOADED_SHA" != "$EXPECTED_ZIP_SHA256" ]; then
        error "SHA256 mismatch!"
        error "  Expected: $EXPECTED_ZIP_SHA256"
        error "  Got:      $DOWNLOADED_SHA"
        rm -f "$CACHE_ZIP"
        exit 1
    fi
    success "SHA256 verified"
fi

# ── Extract ─────────────────────────────────────────────────────────────────
info "Extracting to $DEST_MODELS_DIR..."
TMP_EXTRACT=$(mktemp -d)
unzip -q -o "$CACHE_ZIP" -d "$TMP_EXTRACT"
# HF zip contains RealESRGAN.mlmodel + __MACOSX/ junk
mv "$TMP_EXTRACT/RealESRGAN.mlmodel" "$DEST_MODEL"
rm -rf "$TMP_EXTRACT"

# ── Compile .mlmodel → .mlmodelc ─────────────────────────────────────────────
# Core ML's runtime API loads .mlmodelc (compiled), not .mlmodel (source spec).
# We compile at fetch time so first app launch has no compile lag.
if ! command -v xcrun >/dev/null 2>&1; then
    error "xcrun not found — Xcode command-line tools required for coremlcompiler"
    exit 1
fi

info "Compiling .mlmodel → .mlmodelc..."
# coremlcompiler writes <input-basename>.mlmodelc into the destination directory
rm -rf "$DEST_COMPILED"
xcrun coremlcompiler compile "$DEST_MODEL" "$DEST_MODELS_DIR" 2>&1 | grep -v '^/' || true

if [ ! -d "$DEST_COMPILED" ]; then
    error "Compilation failed — $DEST_COMPILED missing"
    exit 1
fi

# Remove the .mlmodel source after compile — runtime only needs .mlmodelc,
# and source is 64 MB redundancy. fetch-coreml-model.sh re-downloads if needed.
rm -f "$DEST_MODEL"

# ── Mark version ────────────────────────────────────────────────────────────
echo "$SOURCE_VERSION" > "$VERSION_MARKER"

# ── Verify ──────────────────────────────────────────────────────────────────
COMPILED_SIZE=$(du -sk "$DEST_COMPILED" | awk '{print $1*1024}')
success "Core ML compiled model installed"
info "  Compiled: $DEST_COMPILED"
info "  Size:     $(echo "$COMPILED_SIZE" | numfmt --to=iec)"
info "  Version:  $SOURCE_VERSION"
echo ""
info "Attribution: see Resources/models/NOTICES.md"
