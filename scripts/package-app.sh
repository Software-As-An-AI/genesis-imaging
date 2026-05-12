#!/usr/bin/env bash
# scripts/package-app.sh — Assemble .app bundle from `swift build -c release` output
# plus ncnn binary + models bundled under Resources/bin/, plus Sparkle.framework
# bundled under Frameworks/ (required: executable links @rpath/Sparkle.framework/...).
#
# Layout produced:
#   build/GenesisImaging.app/
#     Contents/
#       MacOS/GenesisImaging                       (Swift executable, rpath = ../Frameworks)
#       Info.plist
#       Frameworks/
#         Sparkle.framework/                       (binary framework, Versions/B as Current)
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

# Sparkle.framework — bundled under Contents/Frameworks/. The executable links
# @rpath/Sparkle.framework/Versions/B/Sparkle (compiled by SwiftPM); without the
# framework copy + correct LC_RPATH, the app crashes at launch with:
#   "Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle"
#
# Source candidates (in order of preference; xcframework is canonical for binary
# distributions, the linker copy is a side-effect of SwiftPM):
#   1. .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
#   2. .build/arm64-apple-macosx/release/Sparkle.framework
SPARKLE_FW_SRC=""
SPARKLE_CANDIDATES=(
    ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64/Sparkle.framework"
    ".build/arm64-apple-macosx/release/Sparkle.framework"
)
for cand in "${SPARKLE_CANDIDATES[@]}"; do
    if [ -d "$cand" ]; then
        SPARKLE_FW_SRC="$cand"
        break
    fi
done
if [ -z "$SPARKLE_FW_SRC" ]; then
    echo "[package-app] ✗ Sparkle.framework not found in any candidate path:" >&2
    printf '[package-app]     %s\n' "${SPARKLE_CANDIDATES[@]}" >&2
    echo "[package-app]   Run 'swift build -c release' first (resolves Sparkle SPM dep)." >&2
    exit 1
fi
echo "[package-app] Sparkle source: $SPARKLE_FW_SRC"

mkdir -p "$APP/Contents/Frameworks"
# -R recursive, -P preserve symlinks (critical: framework relies on
# Versions/Current → B and toplevel Sparkle → Versions/Current/Sparkle linkage).
# rsync would also work; cp -RP avoids the rsync dependency.
cp -RP "$SPARKLE_FW_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

# Strip the prebuilt _CodeSignature: signing identity in CI differs from the
# Sparkle distribution's signature. Re-signing happens in release.yml; locally
# this leaves the framework unsigned but loadable.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/_CodeSignature"

# Ensure executable has the rpath entry pointing into Frameworks/. SwiftPM only
# injects @loader_path by default; without @executable_path/../Frameworks the
# dyld lookup fails at launch.
if ! otool -l "$APP/Contents/MacOS/GenesisImaging" | grep -A2 LC_RPATH | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/GenesisImaging"
    echo "[package-app]   ✓ added rpath @executable_path/../Frameworks"
else
    echo "[package-app]   ✓ rpath @executable_path/../Frameworks already present"
fi

# ncnn binary + models
cp "$NCNN_SRC" "$APP/Contents/Resources/bin/realesrgan-ncnn-vulkan"
chmod +x "$APP/Contents/Resources/bin/realesrgan-ncnn-vulkan"
cp -R "$MODELS_SRC/." "$APP/Contents/Resources/bin/models/"

# Smart Output binaries (pngquant + oxipng + libpng + liblcms2 dylibs).
# Used by SmartOutputProcessor for palette-aware post-upscale compression
# (5-20× reduction on B/W / line art / limited-palette content).
# install_name_tool rewrites in pngquant point at @executable_path/<dylib>,
# i.e. siblings of pngquant inside Resources/bin/.
for SMART_BIN in pngquant oxipng liblcms2.2.dylib libpng16.16.dylib; do
    SMART_SRC="Resources/bin/$SMART_BIN"
    if [ -f "$SMART_SRC" ]; then
        cp "$SMART_SRC" "$APP/Contents/Resources/bin/$SMART_BIN"
        chmod +x "$APP/Contents/Resources/bin/$SMART_BIN" 2>/dev/null || true
    else
        echo "[package-app] ! $SMART_SRC missing — Smart Output post-process will degrade gracefully (.auto skips, .always errors)" >&2
    fi
done

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

# Sparkle keys — present only when SU_PUBLIC_KEY env var is set (CI sets it
# from the org-level SPARKLE_ED25519_PRIVATE_KEY pair's public component).
# Local dev builds without the key omit Sparkle config so the app falls back
# to "Sparkle not configured" silently rather than failing on a malformed plist.
SPARKLE_PLIST_BLOCK=""
if [ -n "${SU_PUBLIC_KEY:-}" ]; then
    SPARKLE_PLIST_BLOCK=$(cat << SPARKLE_EOF
  <key>SUFeedURL</key><string>https://apps.softwareasan.ai/genesis-imaging/appcast.xml</string>
  <key>SUPublicEDKey</key><string>${SU_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAllowsAutomaticUpdates</key><true/>
SPARKLE_EOF
)
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
${SPARKLE_PLIST_BLOCK}
</dict>
</plist>
PLIST

echo "[package-app] ✓ $APP"
echo "[package-app]   Executable: $(du -h "$APP/Contents/MacOS/GenesisImaging" | awk '{print $1}')"
echo "[package-app]   Frameworks:"
du -sh "$APP/Contents/Frameworks"/* 2>/dev/null | sed 's/^/[package-app]     /'
echo "[package-app]   Resources:"
du -sh "$APP/Contents/Resources/bin"/* 2>/dev/null | sed 's/^/[package-app]     /'
echo "[package-app]   Total .app size: $(du -sh "$APP" | awk '{print $1}')"
