#!/usr/bin/env bash
# scripts/fetch-smart-output-binaries.sh
#
# Installs pngquant + oxipng (used by SmartOutputProcessor) into
# Resources/bin/ alongside the ncnn binary. Mirrors the fetch-ncnn-binary.sh
# pattern: idempotent, version-marked, gitignored.
#
# Approach for v0.3.1.0: install via Homebrew on the host (dev machine or
# macOS CI runner — both have brew preinstalled), then bundle the binaries +
# pngquant's two dylib deps (libpng, liblcms2) with @executable_path rewrites
# and ad-hoc codesign. release.yml will re-sign with Developer ID before
# notarization.
#
# Future iteration: static build from upstream sources for full reproducibility
# without Homebrew dependency. Tracked: docs/backlog/2026-05-13-smart-output-static-build.md
# (TBD).

set -euo pipefail

# ── Pinned source ───────────────────────────────────────────────────────────
PNGQUANT_VERSION="3.0.3"
OXIPNG_VERSION="10.1.1"
VERSION_MARKER_CONTENT="pngquant-${PNGQUANT_VERSION}+oxipng-${OXIPNG_VERSION}"

# ── Paths ───────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_BIN_DIR="$ROOT/Resources/bin"
VERSION_MARKER="$DEST_BIN_DIR/.smart-output-version"

PNGQUANT="$DEST_BIN_DIR/pngquant"
OXIPNG="$DEST_BIN_DIR/oxipng"
LIBLCMS2="$DEST_BIN_DIR/liblcms2.2.dylib"
LIBPNG="$DEST_BIN_DIR/libpng16.16.dylib"

# ── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[fetch-smart-output]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }

# ── Already installed? ──────────────────────────────────────────────────────
if [ -x "$PNGQUANT" ] && [ -x "$OXIPNG" ] \
   && [ -f "$LIBLCMS2" ] && [ -f "$LIBPNG" ] \
   && [ -f "$VERSION_MARKER" ] \
   && [ "$(cat "$VERSION_MARKER")" = "$VERSION_MARKER_CONTENT" ]; then
    success "Smart Output binaries already installed ($VERSION_MARKER_CONTENT)"
    exit 0
fi

# ── Require brew ───────────────────────────────────────────────────────────
if ! command -v brew >/dev/null 2>&1; then
    error "Homebrew not found. Install from https://brew.sh first."
    error "Future iteration: static build path will remove this dependency."
    exit 1
fi

# ── Install via brew ───────────────────────────────────────────────────────
info "Installing pngquant + oxipng via Homebrew..."
brew install pngquant oxipng

# Resolve binary paths via brew --prefix (more robust than hard-coding /opt/homebrew).
PNGQUANT_SRC="$(brew --prefix pngquant)/bin/pngquant"
OXIPNG_SRC="$(brew --prefix oxipng)/bin/oxipng"
LIBPNG_SRC="$(brew --prefix libpng)/lib/libpng16.16.dylib"
LIBLCMS2_SRC="$(brew --prefix little-cms2)/lib/liblcms2.2.dylib"

for SRC in "$PNGQUANT_SRC" "$OXIPNG_SRC" "$LIBPNG_SRC" "$LIBLCMS2_SRC"; do
    if [ ! -f "$SRC" ]; then
        error "Expected source missing: $SRC"
        exit 1
    fi
done

mkdir -p "$DEST_BIN_DIR"

# ── Copy + chmod ───────────────────────────────────────────────────────────
# Remove existing first — Homebrew-installed binaries land read-only (444),
# which would cause `cp` to fail on re-runs without `--force` semantics.
info "Copying binaries + dylibs..."
rm -f "$PNGQUANT" "$OXIPNG" "$LIBPNG" "$LIBLCMS2"
cp -L "$PNGQUANT_SRC" "$PNGQUANT"
cp -L "$OXIPNG_SRC" "$OXIPNG"
cp -L "$LIBPNG_SRC" "$LIBPNG"
cp -L "$LIBLCMS2_SRC" "$LIBLCMS2"

chmod +wx "$PNGQUANT" "$OXIPNG"
chmod +w  "$LIBPNG" "$LIBLCMS2"

# ── Rewrite install_name (point at @executable_path neighbours) ────────────
info "Rewriting install_name → @executable_path/..."
install_name_tool -change "$LIBLCMS2_SRC" @executable_path/liblcms2.2.dylib "$PNGQUANT"
install_name_tool -change "$LIBPNG_SRC"   @executable_path/libpng16.16.dylib "$PNGQUANT"
install_name_tool -id @executable_path/liblcms2.2.dylib "$LIBLCMS2"
install_name_tool -id @executable_path/libpng16.16.dylib "$LIBPNG"

# ── Ad-hoc re-sign (install_name_tool invalidates Homebrew's signature). ───
# release.yml replaces with Developer ID signature before notarization.
info "Ad-hoc re-signing (install_name_tool invalidates original signature)..."
codesign --force --sign - "$LIBLCMS2"
codesign --force --sign - "$LIBPNG"
codesign --force --sign - "$PNGQUANT"
codesign --force --sign - "$OXIPNG"

# ── Smoke test ─────────────────────────────────────────────────────────────
info "Smoke test..."
"$PNGQUANT" --version >/dev/null
"$OXIPNG" --version >/dev/null

# ── Stamp version marker ───────────────────────────────────────────────────
echo "$VERSION_MARKER_CONTENT" > "$VERSION_MARKER"

success "Smart Output binaries installed:"
info "  pngquant: $(du -h "$PNGQUANT" | awk '{print $1}')"
info "  oxipng:   $(du -h "$OXIPNG"   | awk '{print $1}')"
info "  libpng16: $(du -h "$LIBPNG"   | awk '{print $1}')"
info "  liblcms2: $(du -h "$LIBLCMS2" | awk '{print $1}')"
