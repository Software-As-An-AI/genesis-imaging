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

VERSION="${VERSION:-0.0.0-dev}"
VERSION="${VERSION#v}"  # strip leading "v" if tag-like

EXEC_SRC=".build/release/GenesisImaging"
NCNN_SRC="Resources/bin/realesrgan-ncnn-vulkan"
MODELS_SRC="Resources/bin/models"
ICON_SRC="Resources/AppIcon.icns"

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

# Icon (optional in Faz 1 — workflow does not fail without it)
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
fi

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
