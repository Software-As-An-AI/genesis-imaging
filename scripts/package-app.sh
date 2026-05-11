#!/usr/bin/env bash
# scripts/package-app.sh — Assemble .app bundle from `swift build -c release` output
# plus ncnn binary + models bundled under Resources/bin/.
#
# Layout produced:
#   build/GenesisImaging.app/
#     Contents/
#       MacOS/GenesisImaging                       (Swift executable)
#       Info.plist
#       Resources/
#         bin/realesrgan-ncnn-vulkan
#         bin/models/*.{bin,param}
#         AppIcon.icns                             (if Resources/AppIcon.icns exists)
#
# Env:
#   VERSION (optional) — embedded as CFBundleVersion + CFBundleShortVersionString.
#                        Defaults to "0.0.0-dev".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# VERSION resolution:
#   1. Explicit env override (CI passes ${{ github.ref_name }})
#   2. genesis.json (4-digit Genesis-canonical SSOT)
#   3. Final fallback: 0.0.0-dev
GENESIS_VERSION=$(python3 -c "import json; print(json.load(open('genesis.json')).get('version', ''))" 2>/dev/null || echo "")
VERSION="${VERSION:-${GENESIS_VERSION:-0.0.0-dev}}"
VERSION="${VERSION#v}"  # strip leading "v" if tag-like (e.g. v0.1.2 → 0.1.2)

EXEC_SRC=".build/release/GenesisImaging"
NCNN_SRC="Resources/bin/realesrgan-ncnn-vulkan"
MODELS_SRC="Resources/bin/models"
COREML_MODELS_SRC="Resources/models"
ICON_SRC="Resources/AppIcon.icns"
BUILD_INFO_SRC="$ROOT/BUILD_INFO.json"

if [ ! -x "$EXEC_SRC" ]; then
    echo "[package-app] ✗ $EXEC_SRC missing — run scripts/build.sh first" >&2
    exit 1
fi

if [ ! -x "$NCNN_SRC" ]; then
    echo "[package-app] ✗ $NCNN_SRC missing — run scripts/fetch-ncnn-binary.sh first" >&2
    exit 1
fi

APP="build/GenesisImaging.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/bin/models"

# Executable
cp "$EXEC_SRC" "$APP/Contents/MacOS/GenesisImaging"
chmod +x "$APP/Contents/MacOS/GenesisImaging"

# ncnn binary + models
cp "$NCNN_SRC" "$APP/Contents/Resources/bin/realesrgan-ncnn-vulkan"
chmod +x "$APP/Contents/Resources/bin/realesrgan-ncnn-vulkan"
cp -R "$MODELS_SRC/." "$APP/Contents/Resources/bin/models/"

# Core ML compiled model (Faz 2). NOTICES.md is always copied if present;
# .mlmodelc is conditional so Faz-1-only workflows still package successfully.
mkdir -p "$APP/Contents/Resources/models"
if [ -f "$COREML_MODELS_SRC/NOTICES.md" ]; then
    cp "$COREML_MODELS_SRC/NOTICES.md" "$APP/Contents/Resources/models/NOTICES.md"
fi
if [ -d "$COREML_MODELS_SRC/RealESRGAN_x4plus.mlmodelc" ]; then
    cp -R "$COREML_MODELS_SRC/RealESRGAN_x4plus.mlmodelc" \
          "$APP/Contents/Resources/models/RealESRGAN_x4plus.mlmodelc"
else
    echo "[package-app] ! Core ML model missing — Faz 2 engine will fail at runtime."
    echo "[package-app] !   Run scripts/fetch-coreml-model.sh to install."
fi

# Icon (optional in Faz 1 — workflow does not fail without it)
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
fi

# BUILD_INFO.json — provenance (kulucka pattern). Generate if missing,
# then bundle as Resources/BUILD_INFO.json (app reads at runtime).
if [ ! -f "$BUILD_INFO_SRC" ]; then
    "$ROOT/scripts/generate-build-info.sh"
fi
cp "$BUILD_INFO_SRC" "$APP/Contents/Resources/BUILD_INFO.json"

# Info.plist
cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Genesis Imaging</string>
  <key>CFBundleDisplayName</key><string>Genesis Imaging</string>
  <key>CFBundleIdentifier</key><string>ai.genesis.imaging</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>GenesisImaging</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Okan Yucel · MIT License</string>
</dict>
</plist>
PLIST

echo "[package-app] ✓ $APP"
echo "[package-app]   Executable: $(du -h "$APP/Contents/MacOS/GenesisImaging" | awk '{print $1}')"
echo "[package-app]   Resources:"
du -sh "$APP/Contents/Resources/bin"/* 2>/dev/null | sed 's/^/[package-app]     /'
echo "[package-app]   Total .app size: $(du -sh "$APP" | awk '{print $1}')"
