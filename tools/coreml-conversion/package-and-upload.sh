#!/usr/bin/env bash
# tools/coreml-conversion/package-and-upload.sh
#
# Phase A.3 Step 4 — package the converted Core ML bundle as a zip mirroring
# Apple's nested layout, compute SHA256 + byte count, optionally upload to
# Cloudflare R2.
#
# Inputs:
#   build/coreml-coloring-book/Resources/
#     ├── *.mlmodelc/
#     └── vocab.json + merges.txt
#
# Output layout inside zip (mirrors Apple's palettized bundle pattern so
# SDXLModelCatalog.resourcesSubpath logic stays consistent):
#   coreml-stable-diffusion-xl-coloring-book_compiled/
#   └── compiled/
#       ├── Unet.mlmodelc/
#       ├── TextEncoder.mlmodelc/
#       ├── TextEncoder2.mlmodelc/
#       ├── VAEDecoder.mlmodelc/
#       ├── VAEEncoder.mlmodelc/
#       ├── vocab.json
#       └── merges.txt
#
# Upload mode:
#   - If CLOUDFLARE_API_TOKEN env var set → wrangler r2 object put runs auto
#   - Else → script prints the upload command for operator to run manually
#     after `wrangler login`
#
# Reference: docs/plans/2026-05-17-genesis-imaging-phase-a3-lora-coloring-book.md §Step 4

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_RESOURCES="$HERE/build/coreml-coloring-book/Resources"
TOP_DIR_NAME="coreml-stable-diffusion-xl-coloring-book_compiled"
ZIP_NAME="sdxl-coloring-book-lora-v1.zip"
R2_BUCKET="software-as-an-ai-models"
R2_KEY="$ZIP_NAME"

# Staging area inside build/ (gitignored)
STAGE="$HERE/build/$TOP_DIR_NAME"
ZIP_OUT="$HERE/build/$ZIP_NAME"

# ── Preflight ───────────────────────────────────────────────────────────────
echo "── Preflight ──"
if [ ! -d "$SOURCE_RESOURCES" ]; then
    echo "ERROR: Resources dir missing: $SOURCE_RESOURCES" >&2
    echo "Run Steps 1-2 first." >&2
    exit 1
fi

# Need disk for: source (6.6 GB) + staged copy (6.6 GB) + zip (~6.5 GB) ≈ 20 GB peak.
# We delete staged copy right after zip → net ~6.5 GB.
AVAIL_GB=$(df -g / | tail -1 | awk '{print $4}')
if [ "$AVAIL_GB" -lt 20 ]; then
    echo "ERROR: only ${AVAIL_GB} GB free. Need ≥20 GB for staging + zip." >&2
    exit 1
fi
echo "  disk free: ${AVAIL_GB} GB ✓"

# ── Stage: build the nested directory structure ─────────────────────────────
echo ""
echo "── Staging nested layout ──"
rm -rf "$STAGE"
mkdir -p "$STAGE/compiled"

# ditto preserves resource forks + bundle integrity (.mlmodelc are bundles
# with code signatures). cp -R works but ditto is the macOS canonical tool.
ditto "$SOURCE_RESOURCES/" "$STAGE/compiled/"
echo "  staged $(du -sh "$STAGE" | awk '{print $1}') at $STAGE"

# ── Zip ─────────────────────────────────────────────────────────────────────
echo ""
echo "── Zipping ──"
rm -f "$ZIP_OUT"
( cd "$HERE/build" && zip -qr "$ZIP_NAME" "$TOP_DIR_NAME" )
ZIP_SIZE=$(stat -f %z "$ZIP_OUT")
ZIP_SIZE_GB=$(echo "scale=2; $ZIP_SIZE / 1024 / 1024 / 1024" | bc)
echo "  zip ready: $ZIP_OUT ($ZIP_SIZE bytes, ${ZIP_SIZE_GB} GB)"

# Stage no longer needed; reclaim immediately.
rm -rf "$STAGE"
echo "  staged copy purged (reclaimed ~6.6 GB)"

# ── SHA256 ──────────────────────────────────────────────────────────────────
echo ""
echo "── Computing SHA256 ──"
SHA256=$(shasum -a 256 "$ZIP_OUT" | awk '{print $1}')
echo "  $SHA256"

# ── Output catalog pin ──────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo "Catalog pin (paste into SDXLModelCatalog.Variant.loraColoring):"
echo ""
echo "  expectedSHA256:    $SHA256"
echo "  expectedByteCount: $ZIP_SIZE"
echo "  resourcesSubpath:  $TOP_DIR_NAME/compiled"
echo "──────────────────────────────────────────────────────────────────────"

# ── Upload (auto if token set, else manual) ─────────────────────────────────
echo ""
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo "── Uploading to R2 (CLOUDFLARE_API_TOKEN set) ──"
    wrangler r2 object put "$R2_BUCKET/$R2_KEY" --file "$ZIP_OUT"
    echo ""
    echo "✓ Uploaded to r2://$R2_BUCKET/$R2_KEY"
    echo ""
    echo "Next: enable public access via Cloudflare dashboard OR:"
    echo "  wrangler r2 bucket dev-url enable $R2_BUCKET"
    echo "Then archive URL will be: https://pub-<random>.r2.dev/$R2_KEY"
else
    echo "── Manual upload command (CLOUDFLARE_API_TOKEN not set) ──"
    echo ""
    echo "Run from operator shell after \`wrangler login\`:"
    echo ""
    echo "  cd $HERE/build"
    echo "  wrangler r2 object put $R2_BUCKET/$R2_KEY --file $ZIP_NAME"
    echo ""
    echo "Then enable public access:"
    echo "  wrangler r2 bucket dev-url enable $R2_BUCKET"
fi

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo "Step 4 packaging complete."
echo ""
echo "Optional cleanup post-upload (~6.5 GB reclaim):"
echo "  rm $ZIP_OUT"
echo "──────────────────────────────────────────────────────────────────────"
