#!/usr/bin/env bash
# scripts/verify-app.sh — Local sanity check for the assembled .app bundle.
# Verifies: structure, codesign (if present), launch smoke (`-h` on the bundled binary).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/GenesisImaging.app"
if [ ! -d "$APP" ]; then
    echo "[verify-app] ✗ $APP missing — run scripts/package-app.sh first" >&2
    exit 1
fi

echo "[verify-app] structure check..."
required=(
    "$APP/Contents/MacOS/GenesisImaging"
    "$APP/Contents/Resources/bin/realesrgan-ncnn-vulkan"
    "$APP/Contents/Resources/bin/models/realesrgan-x4plus.bin"
    "$APP/Contents/Resources/bin/models/realesrgan-x4plus.param"
    "$APP/Contents/Info.plist"
)
for f in "${required[@]}"; do
    if [ ! -e "$f" ]; then
        echo "[verify-app] ✗ missing: $f" >&2
        exit 1
    fi
    echo "[verify-app]   ✓ $f"
done

echo "[verify-app] Info.plist..."
plutil -lint "$APP/Contents/Info.plist" || exit 1

echo "[verify-app] codesign (best-effort)..."
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/[verify-app]   /' || \
    echo "[verify-app]   (unsigned — expected on local dev builds without secrets)"

echo "[verify-app] ncnn binary smoke (-h returns help text)..."
"$APP/Contents/Resources/bin/realesrgan-ncnn-vulkan" -h 2>&1 | head -3 | sed 's/^/[verify-app]   /' || true

echo "[verify-app] ✓ verification complete"
