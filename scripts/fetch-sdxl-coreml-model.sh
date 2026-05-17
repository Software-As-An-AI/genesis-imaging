#!/usr/bin/env bash
# scripts/fetch-sdxl-coreml-model.sh
#
# Phase A.2 SDXL bundle integrity check + optional dev pre-download.
#
# v1 default mode: PIN VERIFY ONLY (curl HEAD against HuggingFace LFS, compare
# x-linked-etag against EXPECTED_SHA256, exit 0/1). Used by:
#   - CI weekly drift cron (.github/workflows/sdxl-pin-drift.yml)
#   - manual dev check pre-Step-2 implementation work
#
# v1 download mode (--download flag): fetches the 6.71 GB zip into a local
# cache for dev/test purposes. Production app downloads via URLSession from
# ModelDownloadManager — NOT via this script. Do NOT bundle the file into the
# DMG (DMG stays ~200-300 MB, customer downloads on first launch).
#
# Reference: docs/plans/2026-05-17-genesis-imaging-phase-a2-sdxl-real-pipeline.md
#            §2 Concrete URLs + SHA256 Pinning Protocol

set -euo pipefail

# ── Pinned source (palettized 6.71 GB, openrail++) ──────────────────────────
SOURCE_URL="https://huggingface.co/apple/coreml-stable-diffusion-mixed-bit-palettization/resolve/main/coreml-stable-diffusion-mixed-bit-palettization_original_compiled.zip"
EXPECTED_SHA256="a00f335d990588c97c347d97f7e92080f8cb23342c454f4a4d853a59bea1e2b5"
EXPECTED_SIZE_BYTES="6711666087"
SOURCE_VERSION="palettized-1.0-apple-2023-07"

# ── Paths ───────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$ROOT/.build/cache/sdxl"
CACHE_ZIP="$CACHE_DIR/sdxl-palettized.zip"

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[sdxl-pin]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }

# ── Pin verify (curl HEAD) ──────────────────────────────────────────────────
verify_pin() {
    info "Verifying HF LFS pin (curl HEAD)…"
    info "  URL:  $SOURCE_URL"

    local headers
    if ! headers="$(curl -sIL "$SOURCE_URL" 2>&1)"; then
        error "curl HEAD failed — network or HF outage?"
        exit 2
    fi

    local actual_sha
    actual_sha="$(echo "$headers" | grep -i '^x-linked-etag:' | head -1 \
        | sed -E 's/.*"([a-f0-9]{64})".*/\1/' | tr -d '\r\n')"

    local actual_size
    actual_size="$(echo "$headers" | grep -i '^x-linked-size:' | head -1 \
        | awk '{print $2}' | tr -d '\r\n')"

    if [ -z "$actual_sha" ]; then
        error "Could not extract x-linked-etag from response headers."
        echo "$headers" >&2
        exit 3
    fi

    info "  Pinned SHA256:  $EXPECTED_SHA256"
    info "  Upstream SHA256: $actual_sha"
    info "  Pinned size:    $EXPECTED_SIZE_BYTES bytes"
    info "  Upstream size:   $actual_size bytes"

    if [ "$actual_sha" != "$EXPECTED_SHA256" ]; then
        error "SHA256 MISMATCH — upstream file changed."
        error "  Update EXPECTED_SHA256 in this script + SDXLModelCatalog.swift"
        error "  + investigate: did Apple re-upload? license change? model update?"
        exit 4
    fi

    if [ "$actual_size" != "$EXPECTED_SIZE_BYTES" ]; then
        error "Size MISMATCH — upstream file changed (size: $actual_size vs $EXPECTED_SIZE_BYTES)."
        exit 5
    fi

    success "Pin verified — upstream matches ($SOURCE_VERSION)"
}

# ── Dev download (opt-in, ~6.71 GB) ─────────────────────────────────────────
download_for_dev() {
    if [ -f "$CACHE_ZIP" ]; then
        local cached_sha
        cached_sha="$(shasum -a 256 "$CACHE_ZIP" | awk '{print $1}')"
        if [ "$cached_sha" = "$EXPECTED_SHA256" ]; then
            success "Cached zip already verified ($CACHE_ZIP)"
            info "  Extract with: unzip -q '$CACHE_ZIP' -d <dest>"
            return 0
        else
            warn "Cached zip has wrong SHA — re-downloading"
            rm -f "$CACHE_ZIP"
        fi
    fi

    mkdir -p "$CACHE_DIR"
    info "Downloading 6.71 GB SDXL bundle to $CACHE_ZIP…"
    info "  This will take 5-30 min depending on connection."
    curl -L --fail --progress-bar -o "$CACHE_ZIP" "$SOURCE_URL"

    local sha
    sha="$(shasum -a 256 "$CACHE_ZIP" | awk '{print $1}')"
    if [ "$sha" != "$EXPECTED_SHA256" ]; then
        error "SHA256 verification failed on downloaded file."
        error "  Expected: $EXPECTED_SHA256"
        error "  Got:      $sha"
        rm -f "$CACHE_ZIP"
        exit 6
    fi
    success "Download complete + SHA verified."
    info "  Cache: $CACHE_ZIP"
}

# ── Entry ───────────────────────────────────────────────────────────────────
case "${1:-verify}" in
    verify|--verify|"")
        verify_pin
        ;;
    --download|download)
        verify_pin
        download_for_dev
        ;;
    --help|-h)
        cat <<EOF
Usage: $0 [verify|--download]

Modes:
  verify       (default) curl HEAD HF LFS, compare x-linked-etag vs pinned SHA.
               Exit 0 on match, 4 on mismatch. Used by CI drift cron.

  --download   Verify pin THEN download the 6.71 GB zip to .build/cache/sdxl/
               for dev/test use. Production app downloads via URLSession in
               ModelDownloadManager — do NOT use this for app bundles.

Pinned: $SOURCE_VERSION
SHA256: $EXPECTED_SHA256
EOF
        ;;
    *)
        error "Unknown mode: $1 (use --help)"
        exit 1
        ;;
esac
