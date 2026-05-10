#!/usr/bin/env bash
# scripts/fetch-ncnn-binary.sh
#
# Downloads Real-ESRGAN ncnn-vulkan macOS bundle (binary + bundled models)
# from xinntao/Real-ESRGAN release v0.2.5.0 and places it under Resources/bin/.
#
# Idempotent: skips download if SHA256 of existing zip matches.
# Verifies SHA256 before extraction.

set -euo pipefail

# ── Pinned source ───────────────────────────────────────────────────────────
RELEASE_URL="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-macos.zip"
EXPECTED_SHA256="e0ad05580abfeb25f8d8fb55aaf7bedf552c375b5b4d9bd3c8d59764d2cc333a"
RELEASE_VERSION="20220424"

# ── Paths ───────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_BIN_DIR="$ROOT/Resources/bin"
DEST_MODELS_DIR="$DEST_BIN_DIR/models"
DEST_BINARY="$DEST_BIN_DIR/realesrgan-ncnn-vulkan"
CACHE_DIR="$ROOT/.build/cache/ncnn"
CACHE_ZIP="$CACHE_DIR/realesrgan-ncnn-vulkan-$RELEASE_VERSION-macos.zip"
VERSION_MARKER="$DEST_BIN_DIR/.ncnn-version"

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[fetch-ncnn]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }

# ── Already installed? ──────────────────────────────────────────────────────
if [ -x "$DEST_BINARY" ] && [ -f "$VERSION_MARKER" ]; then
    if [ "$(cat "$VERSION_MARKER")" = "$RELEASE_VERSION" ]; then
        success "ncnn binary already installed (version $RELEASE_VERSION)"
        info "  Binary: $DEST_BINARY"
        info "  Models: $(ls "$DEST_MODELS_DIR"/*.bin 2>/dev/null | wc -l | tr -d ' ') .bin files"
        echo ""
        info "Force re-install: rm $DEST_BINARY $VERSION_MARKER && $0"
        exit 0
    else
        warn "Found older version, will overwrite"
    fi
fi

# ── Download (cached) ───────────────────────────────────────────────────────
mkdir -p "$CACHE_DIR" "$DEST_BIN_DIR" "$DEST_MODELS_DIR"

if [ -f "$CACHE_ZIP" ]; then
    info "Using cached zip: $CACHE_ZIP"
else
    info "Downloading from $RELEASE_URL"
    curl -sL --fail --progress-bar -o "$CACHE_ZIP" "$RELEASE_URL" || {
        error "Download failed"
        rm -f "$CACHE_ZIP"
        exit 1
    }
fi

# ── SHA256 verify ───────────────────────────────────────────────────────────
info "Verifying SHA256..."
ACTUAL_SHA256="$(shasum -a 256 "$CACHE_ZIP" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    error "SHA256 mismatch!"
    error "  Expected: $EXPECTED_SHA256"
    error "  Actual:   $ACTUAL_SHA256"
    error "Possible tampering or corrupted download. Refusing to extract."
    exit 1
fi
success "SHA256 verified"

# ── Extract ─────────────────────────────────────────────────────────────────
info "Extracting to $DEST_BIN_DIR..."
TMP_EXTRACT="$(mktemp -d)"
trap 'rm -rf "$TMP_EXTRACT"' EXIT

unzip -q -o "$CACHE_ZIP" -d "$TMP_EXTRACT"

# Bundle layout (zip root has: binary + models/ + samples)
cp "$TMP_EXTRACT/realesrgan-ncnn-vulkan" "$DEST_BINARY"
chmod +x "$DEST_BINARY"
cp -R "$TMP_EXTRACT/models/." "$DEST_MODELS_DIR/"

# Drop the macOS quarantine attribute if curl set it (rare but possible)
xattr -d com.apple.quarantine "$DEST_BINARY" 2>/dev/null || true

# Record version
echo "$RELEASE_VERSION" > "$VERSION_MARKER"

success "Installed:"
info "  Binary: $DEST_BINARY ($(du -h "$DEST_BINARY" | awk '{print $1}'))"
info "  Models in $DEST_MODELS_DIR:"
for model in "$DEST_MODELS_DIR"/*.bin; do
    [ -f "$model" ] && info "    $(basename "$model" .bin) ($(du -h "$model" | awk '{print $1}'))"
done

# ── Smoke test ──────────────────────────────────────────────────────────────
info ""
info "Running smoke test (input.jpg → 4x upscale)..."
SMOKE_INPUT="$TMP_EXTRACT/input.jpg"
SMOKE_OUTPUT="/tmp/genesis-imaging-smoke-$$.png"

if [ -f "$SMOKE_INPUT" ]; then
    if "$DEST_BINARY" -i "$SMOKE_INPUT" -o "$SMOKE_OUTPUT" \
       -n realesrgan-x4plus -s 4 -t 0 -m "$DEST_MODELS_DIR" 2>&1 | tail -10; then
        if [ -f "$SMOKE_OUTPUT" ]; then
            INPUT_SIZE="$(sips -g pixelWidth -g pixelHeight "$SMOKE_INPUT" | grep -E 'pixel(Width|Height)' | awk '{print $2}' | xargs | tr ' ' 'x')"
            OUTPUT_SIZE="$(sips -g pixelWidth -g pixelHeight "$SMOKE_OUTPUT" | grep -E 'pixel(Width|Height)' | awk '{print $2}' | xargs | tr ' ' 'x')"
            success "Smoke test PASS: $INPUT_SIZE → $OUTPUT_SIZE"
            rm -f "$SMOKE_OUTPUT"
        else
            error "Smoke test FAIL: no output file"
            exit 1
        fi
    else
        error "Smoke test FAIL: binary returned non-zero"
        exit 1
    fi
else
    warn "Smoke test skipped (no sample image in zip)"
fi

success "ncnn-vulkan ready for use."
